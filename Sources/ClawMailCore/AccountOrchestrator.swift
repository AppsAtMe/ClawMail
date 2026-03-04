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

    /// Load config, open database, connect all enabled accounts, start sync.
    public func start() async throws {
        for account in config.accounts where account.isEnabled {
            try await connectAccount(account)
        }

        // Start sync scheduler
        var engines: [String: SyncEngine] = [:]
        for (label, conn) in connections {
            engines[label] = conn.syncEngine
        }
        await syncScheduler.start(
            accounts: config.accounts.filter(\.isEnabled),
            syncEngines: engines
        )
    }

    /// Disconnect all accounts, stop scheduler, close database.
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

        // Guardrail check
        let guardrailResult = try await guardrailEngine.checkSend(
            account: request.account,
            recipients: request.to + (request.cc ?? []) + (request.bcc ?? [])
        )
        switch guardrailResult {
        case .allowed: break
        case .blocked(let error): throw error
        case .pendingApproval(let emails): throw ClawMailError.recipientPendingApproval(emails: emails)
        }

        // Send
        let messageId = try await mgr.sendMessage(request)

        // Audit
        try auditLog.log(entry: AuditEntry(
            interface: agentInterface ?? .cli,
            operation: "email.send",
            account: request.account,
            parameters: [
                "to": .string(request.to.map(\.email).joined(separator: ", ")),
                "subject": .string(request.subject),
            ],
            result: .success,
            details: ["messageId": .string(messageId)]
        ))

        return messageId
    }

    public func replyToMessage(_ request: ReplyEmailRequest) async throws -> String {
        let mgr = try emailManager(for: request.account)
        let messageId = try await mgr.replyToMessage(request)

        try auditLog.log(entry: AuditEntry(
            interface: agentInterface ?? .cli,
            operation: "email.reply",
            account: request.account,
            parameters: [
                "originalMessageId": .string(request.originalMessageId),
                "replyAll": .bool(request.replyAll),
            ],
            result: .success,
            details: ["messageId": .string(messageId)]
        ))

        return messageId
    }

    public func forwardMessage(_ request: ForwardEmailRequest) async throws -> String {
        let mgr = try emailManager(for: request.account)

        let guardrailResult = try await guardrailEngine.checkSend(
            account: request.account,
            recipients: request.to
        )
        switch guardrailResult {
        case .allowed: break
        case .blocked(let error): throw error
        case .pendingApproval(let emails): throw ClawMailError.recipientPendingApproval(emails: emails)
        }

        let messageId = try await mgr.forwardMessage(
            messageId: request.originalMessageId,
            to: request.to,
            body: request.body,
            attachments: request.attachments
        )

        try auditLog.log(entry: AuditEntry(
            interface: agentInterface ?? .cli,
            operation: "email.forward",
            account: request.account,
            parameters: [
                "originalMessageId": .string(request.originalMessageId),
                "to": .string(request.to.map(\.email).joined(separator: ", ")),
            ],
            result: .success,
            details: ["messageId": .string(messageId)]
        ))

        return messageId
    }

    public func moveMessage(account: String, id: String, to folder: String) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.moveMessage(id: id, to: folder)

        try auditLog.log(entry: AuditEntry(
            interface: agentInterface ?? .cli,
            operation: "email.move",
            account: account,
            parameters: ["messageId": .string(id), "destination": .string(folder)],
            result: .success
        ))
    }

    public func deleteMessage(account: String, id: String, permanent: Bool = false) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.deleteMessage(id: id, permanent: permanent)

        try auditLog.log(entry: AuditEntry(
            interface: agentInterface ?? .cli,
            operation: "email.delete",
            account: account,
            parameters: ["messageId": .string(id), "permanent": .bool(permanent)],
            result: .success
        ))
    }

    public func updateFlags(account: String, id: String, add: [EmailFlag] = [], remove: [EmailFlag] = []) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.updateFlags(id: id, add: add, remove: remove)
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
    }

    public func deleteFolder(account: String, path: String) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.deleteFolder(path: path)
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

        try auditLog.log(entry: AuditEntry(
            interface: agentInterface ?? .cli,
            operation: "calendar.create_event",
            account: account,
            parameters: ["title": .string(request.title)],
            result: .success
        ))

        return event
    }

    public func updateEvent(account: String, id: String, _ request: UpdateEventRequest) async throws -> CalendarEvent {
        let mgr = try calendarManager(for: account)
        return try await mgr.updateEvent(id: id, request)
    }

    public func deleteEvent(account: String, id: String) async throws {
        let mgr = try calendarManager(for: account)
        try await mgr.deleteEvent(id: id)
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
        return try await mgr.createContact(request)
    }

    public func updateContact(account: String, id: String, _ request: UpdateContactRequest) async throws -> Contact {
        let mgr = try contactsManager(for: account)
        return try await mgr.updateContact(id: id, request)
    }

    public func deleteContact(account: String, id: String) async throws {
        let mgr = try contactsManager(for: account)
        try await mgr.deleteContact(id: id)
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
        return try await mgr.createTask(request)
    }

    public func updateTask(account: String, id: String, _ request: UpdateTaskRequest) async throws -> TaskItem {
        let mgr = try taskManager(for: account)
        return try await mgr.updateTask(id: id, request)
    }

    public func deleteTask(account: String, id: String) async throws {
        let mgr = try taskManager(for: account)
        try await mgr.deleteTask(id: id)
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

    // MARK: - Pending Approvals

    public func approvePendingRecipients(emails: [String], account: String) throws {
        for email in emails {
            try metadataIndex.approveRecipient(email: email, account: account)
        }
    }

    // MARK: - Internal Helpers

    private func connectAccount(_ account: Account) async throws {
        let credentials = try await credentialStore.credentialsFor(account: account)

        let imapCredential: IMAPCredential
        switch credentials {
        case .password(let password):
            imapCredential = .password(username: account.emailAddress, password: password)
        case .oauth2(let accessToken, _, _):
            imapCredential = .oauth2(username: account.emailAddress, accessToken: accessToken)
        }

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

        // Set up CalDAV/CardDAV if configured
        var calMgr: CalendarManager? = nil
        var contactsMgr: ContactsManager? = nil
        var taskMgr: TaskManager? = nil

        if let caldavURL = account.caldavURL {
            let caldavCred: CalDAVCredential
            switch credentials {
            case .password(let password):
                caldavCred = .password(username: account.emailAddress, password: password)
            case .oauth2(let accessToken, _, _):
                caldavCred = .oauthToken(accessToken)
            }
            let caldavClient = CalDAVClient(baseURL: caldavURL, credential: caldavCred)
            try await caldavClient.authenticate()
            calMgr = CalendarManager(client: caldavClient)
            taskMgr = TaskManager(client: caldavClient)
        }

        if let carddavURL = account.carddavURL {
            let carddavCred: CardDAVCredential
            switch credentials {
            case .password(let password):
                carddavCred = .password(username: account.emailAddress, password: password)
            case .oauth2(let accessToken, _, _):
                carddavCred = .oauthToken(accessToken)
            }
            let carddavClient = CardDAVClient(baseURL: carddavURL, credential: carddavCred)
            try await carddavClient.authenticate()
            contactsMgr = ContactsManager(client: carddavClient)
        }

        let idleMonitor = IMAPIdleMonitor()
        let syncEngine = SyncEngine(
            imapClient: imapClient,
            metadataIndex: metadataIndex,
            accountLabel: account.label
        )

        // Set up IDLE callback
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

    private func emailManager(for account: String) throws -> EmailManager {
        guard let conn = connections[account] else {
            throw ClawMailError.accountNotFound(account)
        }
        return conn.emailManager
    }

    private func calendarManager(for account: String) throws -> CalendarManager {
        guard let conn = connections[account] else {
            throw ClawMailError.accountNotFound(account)
        }
        guard let mgr = conn.calendarManager else {
            throw ClawMailError.calendarNotAvailable
        }
        return mgr
    }

    private func contactsManager(for account: String) throws -> ContactsManager {
        guard let conn = connections[account] else {
            throw ClawMailError.accountNotFound(account)
        }
        guard let mgr = conn.contactsManager else {
            throw ClawMailError.contactsNotAvailable
        }
        return mgr
    }

    private func taskManager(for account: String) throws -> TaskManager {
        guard let conn = connections[account] else {
            throw ClawMailError.accountNotFound(account)
        }
        guard let mgr = conn.taskManager else {
            throw ClawMailError.tasksNotAvailable
        }
        return mgr
    }
}
