import Foundation

/// Per-account connection bundle holding all managers.
public struct AccountConnection: Sendable {
    public let emailManager: EmailManager
    public let calendarManager: CalendarManager?
    public let contactsManager: ContactsManager?
    public let taskManager: TaskManager?
    public let idleMonitor: IMAPIdleMonitor
    public let syncEngine: SyncEngine
}

/// Central coordinator that manages all per-account resources and serves
/// as the single entry point for agent interface layers.
public actor AccountOrchestrator {

    // MARK: - Shared Resources

    private var config: AppConfig
    private let databaseManager: DatabaseManager
    private let metadataIndex: MetadataIndex
    private let auditLog: AuditLog
    private let guardrailEngine: GuardrailEngine
    private let credentialStore: CredentialStore
    private let syncScheduler = SyncScheduler()

    // MARK: - Per-account state

    private var connections: [String: AccountConnection] = [:]
    private var agentInterface: AgentInterface?

    /// Callback for new mail notifications (set by MCP server).
    public var onNewMail: (@Sendable (String, String) -> Void)?

    // MARK: - Init

    public init(config: AppConfig, databaseManager: DatabaseManager) throws {
        self.config = config
        self.databaseManager = databaseManager
        self.metadataIndex = MetadataIndex(db: databaseManager)
        self.auditLog = AuditLog(db: databaseManager)
        let guardrails = config.guardrails
        self.guardrailEngine = GuardrailEngine(
            config: { guardrails },
            auditLog: auditLog,
            metadataIndex: metadataIndex
        )
        self.credentialStore = CredentialStore(keychainManager: KeychainManager())
    }

    // MARK: - Lifecycle

    public func start() async throws {
        for account in config.accounts where account.isEnabled {
            try await connectAccount(account)
        }

        var engines: [String: SyncEngine] = [:]
        for (label, conn) in connections {
            engines[label] = conn.syncEngine
        }
        await syncScheduler.start(
            accounts: config.accounts.filter(\.isEnabled),
            syncEngines: engines
        )
    }

    public func stop() async {
        await syncScheduler.stop()
        for (_, conn) in connections {
            await conn.emailManager.disconnect()
            await conn.idleMonitor.stop()
        }
        connections.removeAll()
    }

    // MARK: - Account Management

    public func addAccount(_ account: Account) async throws {
        config.accounts.append(account)
        try config.save()
        if account.isEnabled {
            try await connectAccount(account)
        }
    }

    public func removeAccount(label: String) async throws {
        if let conn = connections[label] {
            await conn.emailManager.disconnect()
            await conn.idleMonitor.stop()
            connections.removeValue(forKey: label)
        }
        try metadataIndex.purgeAccount(label: label)
        config.accounts.removeAll { $0.label == label }
        try config.save()
    }

    public func listAccounts() -> [Account] {
        config.accounts
    }

    public func getAccount(label: String) -> Account? {
        config.accounts.first { $0.label == label }
    }

    // MARK: - Agent Lock

    public func acquireAgentLock(interface: AgentInterface) -> Bool {
        if agentInterface != nil { return false }
        agentInterface = interface
        return true
    }

    public func releaseAgentLock() {
        agentInterface = nil
    }

    public var isAgentConnected: Bool {
        agentInterface != nil
    }

    // MARK: - Email Operations

    public func listMessages(
        account: String,
        folder: String = "INBOX",
        limit: Int = 50,
        offset: Int = 0,
        sort: SortOrder = .dateDescending
    ) async throws -> [EmailSummary] {
        let mgr = try emailManager(for: account)
        return try await mgr.listMessages(folder: folder, limit: limit, offset: offset, sort: sort)
    }

    public func readMessage(account: String, id: String) async throws -> EmailMessage {
        let mgr = try emailManager(for: account)
        return try await mgr.readMessage(id: id)
    }

    public func sendMessage(_ request: SendEmailRequest) async throws -> String {
        let mgr = try emailManager(for: request.account)

        try await enforceGuardrails(
            account: request.account,
            recipients: request.to + (request.cc ?? []) + (request.bcc ?? [])
        )

        let messageId = try await mgr.sendMessage(request)

        try auditSuccess(
            operation: "email.send",
            account: request.account,
            parameters: [
                "to": .string(request.to.map(\.email).joined(separator: ", ")),
                "subject": .string(request.subject),
            ],
            details: ["messageId": .string(messageId)]
        )

        return messageId
    }

    public func replyToMessage(_ request: ReplyEmailRequest) async throws -> String {
        let mgr = try emailManager(for: request.account)

        // Read original to get recipients for guardrail check
        let original = try await mgr.readMessage(id: request.originalMessageId)
        var recipients = [original.from]
        if request.replyAll {
            recipients += original.to + original.cc
        }
        try await enforceGuardrails(account: request.account, recipients: recipients)

        let messageId = try await mgr.replyToMessage(request)

        try auditSuccess(
            operation: "email.reply",
            account: request.account,
            parameters: [
                "originalMessageId": .string(request.originalMessageId),
                "replyAll": .bool(request.replyAll),
            ],
            details: ["messageId": .string(messageId)]
        )

        return messageId
    }

    public func forwardMessage(_ request: ForwardEmailRequest) async throws -> String {
        let mgr = try emailManager(for: request.account)

        try await enforceGuardrails(account: request.account, recipients: request.to)

        let messageId = try await mgr.forwardMessage(
            messageId: request.originalMessageId,
            to: request.to,
            body: request.body,
            attachments: request.attachments
        )

        try auditSuccess(
            operation: "email.forward",
            account: request.account,
            parameters: [
                "originalMessageId": .string(request.originalMessageId),
                "to": .string(request.to.map(\.email).joined(separator: ", ")),
            ],
            details: ["messageId": .string(messageId)]
        )

        return messageId
    }

    public func moveMessage(account: String, id: String, to folder: String) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.moveMessage(id: id, to: folder)

        try auditSuccess(
            operation: "email.move",
            account: account,
            parameters: ["messageId": .string(id), "destination": .string(folder)]
        )
    }

    public func deleteMessage(account: String, id: String, permanent: Bool = false) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.deleteMessage(id: id, permanent: permanent)

        try auditSuccess(
            operation: "email.delete",
            account: account,
            parameters: ["messageId": .string(id), "permanent": .bool(permanent)]
        )
    }

    public func updateFlags(account: String, id: String, add: [EmailFlag] = [], remove: [EmailFlag] = []) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.updateFlags(id: id, add: add, remove: remove)

        try auditSuccess(
            operation: "email.updateFlags",
            account: account,
            parameters: [
                "messageId": .string(id),
                "add": .string(add.map(\.rawValue).joined(separator: ", ")),
                "remove": .string(remove.map(\.rawValue).joined(separator: ", ")),
            ]
        )
    }

    public func searchMessages(
        account: String,
        query: String,
        folder: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [EmailSummary] {
        let mgr = try emailManager(for: account)
        return try await mgr.searchMessages(query: query, folder: folder, limit: limit, offset: offset)
    }

    public func listFolders(account: String) async throws -> [FolderInfo] {
        let mgr = try emailManager(for: account)
        return try await mgr.listFolders()
    }

    public func createFolder(account: String, name: String, parent: String? = nil) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.createFolder(name: name, parent: parent)

        try auditSuccess(
            operation: "email.createFolder",
            account: account,
            parameters: ["name": .string(name)]
        )
    }

    public func deleteFolder(account: String, path: String) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.deleteFolder(path: path)

        try auditSuccess(
            operation: "email.deleteFolder",
            account: account,
            parameters: ["path": .string(path)]
        )
    }

    public func downloadAttachment(account: String, messageId: String, filename: String, path: String) async throws -> (path: String, size: Int) {
        let mgr = try emailManager(for: account)
        return try await mgr.downloadAttachment(messageId: messageId, filename: filename, destinationPath: path)
    }

    // MARK: - Calendar Operations

    public func listCalendars(account: String) async throws -> [CalendarInfo] {
        let mgr = try calendarManager(for: account)
        return try await mgr.listCalendars()
    }

    public func listEvents(account: String, from: Date, to: Date, calendar: String? = nil) async throws -> [CalendarEvent] {
        let mgr = try calendarManager(for: account)
        return try await mgr.listEvents(from: from, to: to, calendar: calendar)
    }

    public func createEvent(account: String, _ request: CreateEventRequest) async throws -> CalendarEvent {
        let mgr = try calendarManager(for: account)
        let event = try await mgr.createEvent(request)

        try auditSuccess(
            operation: "calendar.createEvent",
            account: account,
            parameters: ["title": .string(request.title)]
        )

        return event
    }

    public func updateEvent(account: String, id: String, _ request: UpdateEventRequest) async throws -> CalendarEvent {
        let mgr = try calendarManager(for: account)
        let event = try await mgr.updateEvent(id: id, request)

        try auditSuccess(
            operation: "calendar.updateEvent",
            account: account,
            parameters: ["id": .string(id)]
        )

        return event
    }

    public func deleteEvent(account: String, id: String) async throws {
        let mgr = try calendarManager(for: account)
        try await mgr.deleteEvent(id: id)

        try auditSuccess(
            operation: "calendar.deleteEvent",
            account: account,
            parameters: ["id": .string(id)]
        )
    }

    // MARK: - Contact Operations

    public func listAddressBooks(account: String) async throws -> [AddressBook] {
        let mgr = try contactsManager(for: account)
        return try await mgr.listAddressBooks()
    }

    public func listContacts(account: String, addressBook: String? = nil, query: String? = nil, limit: Int = 100, offset: Int = 0) async throws -> [Contact] {
        let mgr = try contactsManager(for: account)
        return try await mgr.listContacts(addressBook: addressBook, query: query, limit: limit, offset: offset)
    }

    public func createContact(account: String, _ request: CreateContactRequest) async throws -> Contact {
        let mgr = try contactsManager(for: account)
        let contact = try await mgr.createContact(request)

        try auditSuccess(
            operation: "contacts.create",
            account: account,
            parameters: ["displayName": .string(request.displayName)]
        )

        return contact
    }

    public func updateContact(account: String, id: String, _ request: UpdateContactRequest) async throws -> Contact {
        let mgr = try contactsManager(for: account)
        let contact = try await mgr.updateContact(id: id, request)

        try auditSuccess(
            operation: "contacts.update",
            account: account,
            parameters: ["id": .string(id)]
        )

        return contact
    }

    public func deleteContact(account: String, id: String) async throws {
        let mgr = try contactsManager(for: account)
        try await mgr.deleteContact(id: id)

        try auditSuccess(
            operation: "contacts.delete",
            account: account,
            parameters: ["id": .string(id)]
        )
    }

    // MARK: - Task Operations

    public func listTaskLists(account: String) async throws -> [TaskList] {
        let mgr = try taskManager(for: account)
        return try await mgr.listTaskLists()
    }

    public func listTasks(account: String, taskList: String? = nil, includeCompleted: Bool = false) async throws -> [TaskItem] {
        let mgr = try taskManager(for: account)
        return try await mgr.listTasks(taskList: taskList, includeCompleted: includeCompleted)
    }

    public func createTask(account: String, _ request: CreateTaskRequest) async throws -> TaskItem {
        let mgr = try taskManager(for: account)
        let task = try await mgr.createTask(request)

        try auditSuccess(
            operation: "tasks.create",
            account: account,
            parameters: ["title": .string(request.title)]
        )

        return task
    }

    public func updateTask(account: String, id: String, _ request: UpdateTaskRequest) async throws -> TaskItem {
        let mgr = try taskManager(for: account)
        let task = try await mgr.updateTask(id: id, request)

        try auditSuccess(
            operation: "tasks.update",
            account: account,
            parameters: ["id": .string(id)]
        )

        return task
    }

    public func deleteTask(account: String, id: String) async throws {
        let mgr = try taskManager(for: account)
        try await mgr.deleteTask(id: id)

        try auditSuccess(
            operation: "tasks.delete",
            account: account,
            parameters: ["id": .string(id)]
        )
    }

    // MARK: - Audit

    public func getAuditLog(account: String? = nil, limit: Int = 100) throws -> [AuditEntry] {
        try auditLog.list(limit: limit, account: account)
    }

    // MARK: - Approved Recipients

    public func listApprovedRecipients(account: String? = nil) throws -> [(email: String, approvedAt: Date)] {
        try metadataIndex.listApprovedRecipients(account: account)
    }

    public func approveRecipient(email: String, account: String) throws {
        try metadataIndex.approveRecipient(email: email, account: account)
    }

    public func removeApprovedRecipient(email: String) throws {
        try metadataIndex.removeApprovedRecipient(email: email)
    }

    public func approvePendingRecipients(emails: [String], account: String) throws {
        for email in emails {
            try metadataIndex.approveRecipient(email: email, account: account)
        }
    }

    // MARK: - Internal Helpers

    private func enforceGuardrails(account: String, recipients: [EmailAddress]) async throws {
        let result = try await guardrailEngine.checkSend(account: account, recipients: recipients)
        switch result {
        case .allowed: break
        case .blocked(let error): throw error
        case .pendingApproval(let emails): throw ClawMailError.recipientPendingApproval(emails: emails)
        }
    }

    private func auditSuccess(
        operation: String,
        account: String,
        parameters: [String: AnyCodableValue],
        details: [String: AnyCodableValue]? = nil
    ) throws {
        try auditLog.log(entry: AuditEntry(
            interface: agentInterface ?? .cli,
            operation: operation,
            account: account,
            parameters: parameters,
            result: .success,
            details: details
        ))
    }

    private func connectAccount(_ account: Account) async throws {
        let credentials = try await credentialStore.credentialsFor(account: account)

        let imapCredential = credentials.imapCredential(username: account.emailAddress)

        let imapClient = IMAPClient(
            host: account.imapHost,
            port: account.imapPort,
            security: account.imapSecurity,
            credential: imapCredential
        )

        let smtpClient = SMTPClient(
            host: account.smtpHost,
            port: account.smtpPort,
            security: account.smtpSecurity,
            credentials: credentials,
            senderEmail: account.emailAddress
        )

        let emailManager = EmailManager(
            account: account,
            imapClient: imapClient,
            smtpClient: smtpClient,
            metadataIndex: metadataIndex
        )

        try await emailManager.connect()

        var calMgr: CalendarManager? = nil
        var contactsMgr: ContactsManager? = nil
        var taskMgr: TaskManager? = nil

        if let caldavURL = account.caldavURL {
            let caldavClient = CalDAVClient(
                baseURL: caldavURL,
                credential: credentials.calDAVCredential(username: account.emailAddress)
            )
            try await caldavClient.authenticate()
            calMgr = CalendarManager(client: caldavClient)
            taskMgr = TaskManager(client: caldavClient)
        }

        if let carddavURL = account.carddavURL {
            let carddavClient = CardDAVClient(
                baseURL: carddavURL,
                credential: credentials.cardDAVCredential(username: account.emailAddress)
            )
            try await carddavClient.authenticate()
            contactsMgr = ContactsManager(client: carddavClient)
        }

        let idleMonitor = IMAPIdleMonitor()
        let syncEngine = SyncEngine(
            imapClient: imapClient,
            metadataIndex: metadataIndex,
            accountLabel: account.label
        )

        let newMailCallback = onNewMail
        let sEngine = syncEngine
        try await idleMonitor.start(
            account: account,
            credential: imapCredential,
            folders: ["INBOX"],
            onNewMail: { [newMailCallback, sEngine] accountLabel, folder in
                Task {
                    try? await sEngine.handleNewMail(folder: folder)
                }
                newMailCallback?(accountLabel, folder)
            }
        )

        connections[account.label] = AccountConnection(
            emailManager: emailManager,
            calendarManager: calMgr,
            contactsManager: contactsMgr,
            taskManager: taskMgr,
            idleMonitor: idleMonitor,
            syncEngine: syncEngine
        )
    }

    private func requireConnection(for account: String) throws -> AccountConnection {
        guard let conn = connections[account] else {
            throw ClawMailError.accountNotFound(account)
        }
        return conn
    }

    private func emailManager(for account: String) throws -> EmailManager {
        try requireConnection(for: account).emailManager
    }

    private func requireManager<T>(
        for account: String,
        keyPath: KeyPath<AccountConnection, T?>,
        unavailableError: ClawMailError
    ) throws -> T {
        let conn = try requireConnection(for: account)
        guard let mgr = conn[keyPath: keyPath] else {
            throw unavailableError
        }
        return mgr
    }

    private func calendarManager(for account: String) throws -> CalendarManager {
        try requireManager(for: account, keyPath: \.calendarManager, unavailableError: .calendarNotAvailable)
    }

    private func contactsManager(for account: String) throws -> ContactsManager {
        try requireManager(for: account, keyPath: \.contactsManager, unavailableError: .contactsNotAvailable)
    }

    private func taskManager(for account: String) throws -> TaskManager {
        try requireManager(for: account, keyPath: \.taskManager, unavailableError: .tasksNotAvailable)
    }
}

// MARK: - Credential Conversion Helpers

extension Credentials {
    func imapCredential(username: String) -> IMAPCredential {
        switch self {
        case .password(let password):
            return .password(username: username, password: password)
        case .oauth2(let accessToken, _, _):
            return .oauth2(username: username, accessToken: accessToken)
        }
    }

    func calDAVCredential(username: String) -> CalDAVCredential {
        switch self {
        case .password(let password):
            return .password(username: username, password: password)
        case .oauth2(let accessToken, _, _):
            return .oauthToken(accessToken)
        }
    }

    func cardDAVCredential(username: String) -> CardDAVCredential {
        switch self {
        case .password(let password):
            return .password(username: username, password: password)
        case .oauth2(let accessToken, _, _):
            return .oauthToken(accessToken)
        }
    }
}
