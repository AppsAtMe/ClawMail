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

/// Thread-safe mutable box used to pass live GuardrailConfig into the
/// GuardrailEngine closure without violating Swift 6 init rules.
private final class GuardrailConfigRef: @unchecked Sendable {
    private var _value: GuardrailConfig
    private let lock = NSLock()

    init(_ value: GuardrailConfig) { _value = value }

    var value: GuardrailConfig {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Central coordinator that manages all per-account resources and serves
/// as the single entry point for agent interface layers.
public actor AccountOrchestrator {
    typealias PendingApprovalReplayHandler = @Sendable (PendingApprovalRequestEnvelope) async throws -> String

    // MARK: - Shared Resources

    private var config: AppConfig
    private let databaseManager: DatabaseManager
    private let metadataIndex: MetadataIndex
    private let auditLog: AuditLog
    private let guardrailEngine: GuardrailEngine
    private let guardrailConfigRef: GuardrailConfigRef
    private let credentialStore: CredentialStore
    private let saveConfig: @Sendable (AppConfig) throws -> Void
    private let syncScheduler = SyncScheduler()
    private let pendingApprovalReplayHandler: PendingApprovalReplayHandler?

    // MARK: - Per-account state

    private var connections: [String: AccountConnection] = [:]
    private var agentSessionActive = false

    /// Callback for new mail notifications (account label, folder).
    public var onNewMail: (@Sendable (String, String) -> Void)?

    /// Callback for connection status changes (account label, new status).
    public var onConnectionStatusChanged: (@Sendable (String, ConnectionStatus) -> Void)?

    /// Callback for errors (account label, error description).
    public var onError: (@Sendable (String, String) -> Void)?

    /// Callback for pending recipient approval (account label, pending emails).
    public var onPendingApproval: (@Sendable (String, [String]) -> Void)?

    // MARK: - Init

    public init(
        config: AppConfig,
        databaseManager: DatabaseManager,
        credentialStore: CredentialStore? = nil,
        configSaver: @escaping @Sendable (AppConfig) throws -> Void = { try $0.save() }
    ) throws {
        try self.init(
            config: config,
            databaseManager: databaseManager,
            credentialStore: credentialStore,
            configSaver: configSaver,
            pendingApprovalReplayHandler: nil
        )
    }

    init(
        config: AppConfig,
        databaseManager: DatabaseManager,
        credentialStore: CredentialStore? = nil,
        configSaver: @escaping @Sendable (AppConfig) throws -> Void = { try $0.save() },
        pendingApprovalReplayHandler: PendingApprovalReplayHandler?
    ) throws {
        self.config = config
        self.databaseManager = databaseManager
        self.metadataIndex = MetadataIndex(db: databaseManager)
        self.auditLog = AuditLog(db: databaseManager)
        self.credentialStore = credentialStore ?? CredentialStore(keychainManager: KeychainManager())
        self.saveConfig = configSaver
        self.pendingApprovalReplayHandler = pendingApprovalReplayHandler
        // Use a reference-type box so the closure always reads the live config value.
        // Capturing a struct directly would freeze guardrail settings at startup.
        let ref = GuardrailConfigRef(config.guardrails)
        self.guardrailConfigRef = ref
        self.guardrailEngine = GuardrailEngine(
            config: { ref.value },
            auditLog: auditLog,
            metadataIndex: metadataIndex
        )
    }

    /// Apply updated guardrail settings immediately without restarting the daemon.
    public func updateGuardrailConfig(_ guardrails: GuardrailConfig) async {
        let approvalWasEnabled = guardrailConfigRef.value.firstTimeRecipientApproval
        config.guardrails = guardrails
        guardrailConfigRef.value = guardrails

        guard approvalWasEnabled, !guardrails.firstTimeRecipientApproval else {
            return
        }

        for account in config.accounts.map(\.label) {
            do {
                try await releaseReadyPendingApprovals(account: account)
            } catch {
                onError?(account, "Failed to release pending approvals: \(error)")
            }
        }
    }

    public func updateSyncSettings(
        syncIntervalMinutes: Int,
        initialSyncDays: Int,
        idleFolders: [String]
    ) async throws {
        config.syncIntervalMinutes = max(syncIntervalMinutes, 1)
        config.initialSyncDays = max(initialSyncDays, 1)
        config.idleFolders = Self.normalizedIdleFolders(idleFolders)

        try await restartIdleMonitoring()
        await restartSyncScheduler()
    }

    /// Set all notification callbacks at once.
    public func setCallbacks(
        onNewMail: @escaping @Sendable (String, String) -> Void,
        onConnectionStatusChanged: @escaping @Sendable (String, ConnectionStatus) -> Void,
        onError: @escaping @Sendable (String, String) -> Void
    ) async {
        self.onNewMail = onNewMail
        self.onConnectionStatusChanged = onConnectionStatusChanged
        self.onError = onError
        await syncScheduler.setErrorHandler(onError)
    }

    /// Set callback for pending recipient approval notifications.
    public func setPendingApprovalCallback(_ callback: @escaping @Sendable (String, [String]) -> Void) {
        self.onPendingApproval = callback
    }

    // MARK: - Lifecycle

    public func start() async throws {
        for account in config.accounts where account.isEnabled {
            try await connectAccount(account)
        }
        await restartSyncScheduler()
    }

    public func stop() async {
        await syncScheduler.stop()
        for (label, conn) in connections {
            await conn.emailManager.disconnect()
            await conn.idleMonitor.stop()
            if let idx = config.accounts.firstIndex(where: { $0.label == label }) {
                config.accounts[idx].connectionStatus = .disconnected
            }
            onConnectionStatusChanged?(label, .disconnected)
            auditEvent(
                interface: .app,
                operation: "account.disconnect",
                account: label,
                parameters: ["reason": .string("app-stop")]
            )
        }
        connections.removeAll()
    }

    // MARK: - Account Management

    public func addAccount(_ account: Account) async throws {
        config.accounts.append(account)
        try saveConfig(config)
        do {
            if account.isEnabled {
                try await connectAccount(account)
            }
        } catch {
            config.accounts.removeAll { $0.id == account.id }
            try? saveConfig(config)
            throw error
        }
        auditEvent(
            interface: .app,
            operation: "account.add",
            account: account.label,
            parameters: ["email": .string(account.emailAddress)]
        )
        await restartSyncScheduler()
    }

    public func removeAccount(label: String) async throws {
        let account = config.accounts.first { $0.label == label }

        if let conn = connections[label] {
            await conn.emailManager.disconnect()
            await conn.idleMonitor.stop()
            connections.removeValue(forKey: label)
            onConnectionStatusChanged?(label, .disconnected)
        }
        if let account {
            try await credentialStore.deleteCredentials(accountId: account.id)
        }
        try metadataIndex.purgeAccount(label: label)
        config.accounts.removeAll { $0.label == label }
        try saveConfig(config)
        auditEvent(
            interface: .app,
            operation: "account.remove",
            account: label
        )
        await restartSyncScheduler()
    }

    public func updateAccount(label: String, with updatedAccount: Account) async throws {
        guard let index = config.accounts.firstIndex(where: { $0.label == label }) else {
            throw ClawMailError.accountNotFound(label)
        }

        let existingAccount = config.accounts[index]
        guard existingAccount.id == updatedAccount.id else {
            throw ClawMailError.invalidParameter("Updated account ID must match the existing account ID.")
        }
        guard updatedAccount.label == label else {
            throw ClawMailError.invalidParameter("Renaming accounts is not supported yet.")
        }

        if let connection = connections[label] {
            await connection.emailManager.disconnect()
            await connection.idleMonitor.stop()
            connections.removeValue(forKey: label)
            onConnectionStatusChanged?(label, .disconnected)
        }

        config.accounts[index] = updatedAccount

        do {
            try saveConfig(config)

            if updatedAccount.isEnabled {
                try await connectAccount(updatedAccount)
            } else if let updatedIndex = config.accounts.firstIndex(where: { $0.label == label }) {
                config.accounts[updatedIndex].connectionStatus = .disconnected
                onConnectionStatusChanged?(label, .disconnected)
            }

            auditEvent(
                interface: .app,
                operation: "account.update",
                account: label,
                parameters: ["email": .string(updatedAccount.emailAddress)]
            )
            await restartSyncScheduler()
        } catch {
            config.accounts[index] = existingAccount
            try? saveConfig(config)

            if existingAccount.isEnabled {
                do {
                    try await connectAccount(existingAccount)
                } catch {
                    onError?(label, "Failed to restore previous account settings: \(Self.describe(error))")
                }
            }

            throw error
        }
    }

    public func listAccounts() -> [Account] {
        config.accounts
    }

    public func getAccount(label: String) -> Account? {
        config.accounts.first { $0.label == label }
    }

    // MARK: - Agent Lock

    public func acquireAgentLock(interface: AgentInterface) -> Bool {
        if agentSessionActive { return false }
        agentSessionActive = true
        return true
    }

    public func releaseAgentLock() {
        agentSessionActive = false
    }

    public var isAgentConnected: Bool {
        agentSessionActive
    }

    // MARK: - Email Operations

    public func listMessages(
        account: String,
        folder: String = "INBOX",
        limit: Int = 50,
        offset: Int = 0,
        sort: SortOrder = .dateDescending,
        interface: AgentInterface = .cli
    ) async throws -> [EmailSummary] {
        let mgr = try emailManager(for: account)
        let messages = try await mgr.listMessages(folder: folder, limit: limit, offset: offset, sort: sort)

        try auditSuccess(
            interface: interface,
            operation: "email.list",
            account: account,
            parameters: [
                "folder": .string(folder),
                "limit": .int(limit),
                "offset": .int(offset),
                "sort": .string(sort.rawValue),
            ],
            details: ["count": .int(messages.count)]
        )

        return messages
    }

    public func readMessage(account: String, id: String, interface: AgentInterface = .cli) async throws -> EmailMessage {
        let mgr = try emailManager(for: account)
        let message = try await mgr.readMessage(id: id)

        try auditSuccess(
            interface: interface,
            operation: "email.read",
            account: account,
            parameters: ["messageId": .string(id)]
        )

        return message
    }

    public func sendMessage(_ request: SendEmailRequest, interface: AgentInterface = .cli) async throws -> String {
        let mgr = try emailManager(for: request.account)

        try await enforceGuardrails(
            account: request.account,
            recipients: request.to + (request.cc ?? []) + (request.bcc ?? []),
            heldRequest: PendingApprovalRequestEnvelope(
                interface: interface,
                payload: .send(request)
            )
        )

        let messageId = try await mgr.sendMessage(request)

        try auditSuccess(
            interface: interface,
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

    public func replyToMessage(_ request: ReplyEmailRequest, interface: AgentInterface = .cli) async throws -> String {
        let mgr = try emailManager(for: request.account)

        // Read original to get recipients for guardrail check
        let original = try await mgr.readMessage(id: request.originalMessageId)
        var recipients = [original.from]
        if request.replyAll {
            recipients += original.to + original.cc
        }
        try await enforceGuardrails(
            account: request.account,
            recipients: recipients,
            heldRequest: PendingApprovalRequestEnvelope(
                interface: interface,
                payload: .reply(request)
            )
        )

        let messageId = try await mgr.replyToMessage(request)

        try auditSuccess(
            interface: interface,
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

    public func forwardMessage(_ request: ForwardEmailRequest, interface: AgentInterface = .cli) async throws -> String {
        let mgr = try emailManager(for: request.account)

        try await enforceGuardrails(
            account: request.account,
            recipients: request.to,
            heldRequest: PendingApprovalRequestEnvelope(
                interface: interface,
                payload: .forward(request)
            )
        )

        let messageId = try await mgr.forwardMessage(
            messageId: request.originalMessageId,
            to: request.to,
            body: request.body,
            attachments: request.attachments
        )

        try auditSuccess(
            interface: interface,
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

    public func moveMessage(account: String, id: String, to folder: String, interface: AgentInterface = .cli) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.moveMessage(id: id, to: folder)

        try auditSuccess(
            interface: interface,
            operation: "email.move",
            account: account,
            parameters: ["messageId": .string(id), "destination": .string(folder)]
        )
    }

    public func deleteMessage(account: String, id: String, permanent: Bool = false, interface: AgentInterface = .cli) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.deleteMessage(id: id, permanent: permanent)

        try auditSuccess(
            interface: interface,
            operation: "email.delete",
            account: account,
            parameters: ["messageId": .string(id), "permanent": .bool(permanent)]
        )
    }

    @discardableResult
    public func updateFlags(account: String, id: String, add: [EmailFlag] = [], remove: [EmailFlag] = [], interface: AgentInterface = .cli) async throws -> EmailSummary {
        let mgr = try emailManager(for: account)
        let updated = try await mgr.updateFlags(id: id, add: add, remove: remove)

        try auditSuccess(
            interface: interface,
            operation: "email.updateFlags",
            account: account,
            parameters: [
                "messageId": .string(id),
                "add": .string(add.map(\.rawValue).joined(separator: ", ")),
                "remove": .string(remove.map(\.rawValue).joined(separator: ", ")),
            ]
        )

        return updated
    }

    public func searchMessages(
        account: String,
        query: String,
        folder: String? = nil,
        limit: Int = 50,
        offset: Int = 0,
        interface: AgentInterface = .cli
    ) async throws -> [EmailSummary] {
        let mgr = try emailManager(for: account)
        let messages = try await mgr.searchMessages(query: query, folder: folder, limit: limit, offset: offset)

        try auditSuccess(
            interface: interface,
            operation: "email.search",
            account: account,
            parameters: [
                "query": .string(query),
                "folder": folder.map(AnyCodableValue.string) ?? .null,
                "limit": .int(limit),
                "offset": .int(offset),
            ],
            details: ["count": .int(messages.count)]
        )

        return messages
    }

    public func listFolders(account: String, interface: AgentInterface = .cli) async throws -> [FolderInfo] {
        let mgr = try emailManager(for: account)
        let folders = try await mgr.listFolders()

        try auditSuccess(
            interface: interface,
            operation: "email.listFolders",
            account: account,
            parameters: [:],
            details: ["count": .int(folders.count)]
        )

        return folders
    }

    public func createFolder(account: String, name: String, parent: String? = nil, interface: AgentInterface = .cli) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.createFolder(name: name, parent: parent)

        try auditSuccess(
            interface: interface,
            operation: "email.createFolder",
            account: account,
            parameters: ["name": .string(name)]
        )
    }

    public func deleteFolder(account: String, path: String, interface: AgentInterface = .cli) async throws {
        let mgr = try emailManager(for: account)
        try await mgr.deleteFolder(path: path)

        try auditSuccess(
            interface: interface,
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

    public func listCalendars(account: String, interface: AgentInterface = .cli) async throws -> [CalendarInfo] {
        let mgr = try calendarManager(for: account)
        let calendars = try await mgr.listCalendars()

        try auditSuccess(
            interface: interface,
            operation: "calendar.listCalendars",
            account: account,
            parameters: [:],
            details: ["count": .int(calendars.count)]
        )

        return calendars
    }

    public func listEvents(account: String, from: Date, to: Date, calendar: String? = nil, interface: AgentInterface = .cli) async throws -> [CalendarEvent] {
        let mgr = try calendarManager(for: account)
        let events = try await mgr.listEvents(from: from, to: to, calendar: calendar)

        try auditSuccess(
            interface: interface,
            operation: "calendar.listEvents",
            account: account,
            parameters: [
                "from": .string(from.ISO8601Format()),
                "to": .string(to.ISO8601Format()),
                "calendar": calendar.map(AnyCodableValue.string) ?? .null,
            ],
            details: ["count": .int(events.count)]
        )

        return events
    }

    public func createEvent(account: String, _ request: CreateEventRequest, interface: AgentInterface = .cli) async throws -> CalendarEvent {
        let mgr = try calendarManager(for: account)
        let event = try await mgr.createEvent(request)

        try auditSuccess(
            interface: interface,
            operation: "calendar.createEvent",
            account: account,
            parameters: ["title": .string(request.title)]
        )

        return event
    }

    public func updateEvent(account: String, id: String, _ request: UpdateEventRequest, interface: AgentInterface = .cli) async throws -> CalendarEvent {
        let mgr = try calendarManager(for: account)
        let event = try await mgr.updateEvent(id: id, request)

        try auditSuccess(
            interface: interface,
            operation: "calendar.updateEvent",
            account: account,
            parameters: ["id": .string(id)]
        )

        return event
    }

    public func deleteEvent(account: String, id: String, interface: AgentInterface = .cli) async throws {
        let mgr = try calendarManager(for: account)
        try await mgr.deleteEvent(id: id)

        try auditSuccess(
            interface: interface,
            operation: "calendar.deleteEvent",
            account: account,
            parameters: ["id": .string(id)]
        )
    }

    // MARK: - Contact Operations

    public func listAddressBooks(account: String, interface: AgentInterface = .cli) async throws -> [AddressBook] {
        let mgr = try contactsManager(for: account)
        let addressBooks = try await mgr.listAddressBooks()

        try auditSuccess(
            interface: interface,
            operation: "contacts.listAddressBooks",
            account: account,
            parameters: [:],
            details: ["count": .int(addressBooks.count)]
        )

        return addressBooks
    }

    public func listContacts(
        account: String,
        addressBook: String? = nil,
        query: String? = nil,
        limit: Int = 100,
        offset: Int = 0,
        interface: AgentInterface = .cli
    ) async throws -> [Contact] {
        let mgr = try contactsManager(for: account)
        let contacts = try await mgr.listContacts(addressBook: addressBook, query: query, limit: limit, offset: offset)

        try auditSuccess(
            interface: interface,
            operation: "contacts.list",
            account: account,
            parameters: [
                "addressBook": addressBook.map(AnyCodableValue.string) ?? .null,
                "query": query.map(AnyCodableValue.string) ?? .null,
                "limit": .int(limit),
                "offset": .int(offset),
            ],
            details: ["count": .int(contacts.count)]
        )

        return contacts
    }

    public func createContact(account: String, _ request: CreateContactRequest, interface: AgentInterface = .cli) async throws -> Contact {
        let mgr = try contactsManager(for: account)
        let contact = try await mgr.createContact(request)

        try auditSuccess(
            interface: interface,
            operation: "contacts.create",
            account: account,
            parameters: ["displayName": .string(request.displayName)]
        )

        return contact
    }

    public func updateContact(account: String, id: String, _ request: UpdateContactRequest, interface: AgentInterface = .cli) async throws -> Contact {
        let mgr = try contactsManager(for: account)
        let contact = try await mgr.updateContact(id: id, request)

        try auditSuccess(
            interface: interface,
            operation: "contacts.update",
            account: account,
            parameters: ["id": .string(id)]
        )

        return contact
    }

    public func deleteContact(account: String, id: String, interface: AgentInterface = .cli) async throws {
        let mgr = try contactsManager(for: account)
        try await mgr.deleteContact(id: id)

        try auditSuccess(
            interface: interface,
            operation: "contacts.delete",
            account: account,
            parameters: ["id": .string(id)]
        )
    }

    // MARK: - Task Operations

    public func listTaskLists(account: String, interface: AgentInterface = .cli) async throws -> [TaskList] {
        let mgr = try taskManager(for: account)
        let taskLists = try await mgr.listTaskLists()

        try auditSuccess(
            interface: interface,
            operation: "tasks.listTaskLists",
            account: account,
            parameters: [:],
            details: ["count": .int(taskLists.count)]
        )

        return taskLists
    }

    public func listTasks(
        account: String,
        taskList: String? = nil,
        includeCompleted: Bool = false,
        interface: AgentInterface = .cli
    ) async throws -> [TaskItem] {
        let mgr = try taskManager(for: account)
        let tasks = try await mgr.listTasks(taskList: taskList, includeCompleted: includeCompleted)

        try auditSuccess(
            interface: interface,
            operation: "tasks.list",
            account: account,
            parameters: [
                "taskList": taskList.map(AnyCodableValue.string) ?? .null,
                "includeCompleted": .bool(includeCompleted),
            ],
            details: ["count": .int(tasks.count)]
        )

        return tasks
    }

    public func createTask(account: String, _ request: CreateTaskRequest, interface: AgentInterface = .cli) async throws -> TaskItem {
        let mgr = try taskManager(for: account)
        let task = try await mgr.createTask(request)

        try auditSuccess(
            interface: interface,
            operation: "tasks.create",
            account: account,
            parameters: ["title": .string(request.title)]
        )

        return task
    }

    public func updateTask(account: String, id: String, _ request: UpdateTaskRequest, interface: AgentInterface = .cli) async throws -> TaskItem {
        let mgr = try taskManager(for: account)
        let task = try await mgr.updateTask(id: id, request)

        try auditSuccess(
            interface: interface,
            operation: "tasks.update",
            account: account,
            parameters: ["id": .string(id)]
        )

        return task
    }

    public func deleteTask(account: String, id: String, interface: AgentInterface = .cli) async throws {
        let mgr = try taskManager(for: account)
        try await mgr.deleteTask(id: id)

        try auditSuccess(
            interface: interface,
            operation: "tasks.delete",
            account: account,
            parameters: ["id": .string(id)]
        )
    }

    // MARK: - Audit

    public func getAuditLog(account: String? = nil, limit: Int = 100, offset: Int = 0) throws -> [AuditEntry] {
        try auditLog.list(limit: limit, offset: offset, account: account)
    }

    // MARK: - Approved Recipients

    public func listApprovedRecipients(account: String? = nil) throws -> [ApprovedRecipient] {
        try metadataIndex.listApprovedRecipients(account: account)
    }

    public func listPendingApprovals(account: String? = nil) throws -> [PendingApproval] {
        try metadataIndex.listPendingApprovals(account: account)
    }

    public func approveRecipient(email: String, account: String) async throws {
        try metadataIndex.approveRecipient(email: email, account: account)
        try await releaseReadyPendingApprovals(account: account)
    }

    public func removeApprovedRecipient(email: String, account: String) throws {
        try metadataIndex.removeApprovedRecipient(email: email, account: account)
    }

    public func approvePendingRecipients(emails: [String], account: String) async throws {
        for email in emails {
            try metadataIndex.approveRecipient(email: email, account: account)
        }
        try await releaseReadyPendingApprovals(account: account)
    }

    public func approvePendingApproval(requestId: String, account: String) async throws {
        guard let approval = try metadataIndex.listPendingApprovals(account: account)
            .first(where: { $0.requestId == requestId }) else {
            throw ClawMailError.invalidParameter("Pending approval '\(requestId)' not found for account '\(account)'")
        }

        for email in approval.emails {
            try metadataIndex.approveRecipient(email: email, account: account)
        }

        try await releasePendingApproval(requestId: requestId, account: account)
    }

    public func rejectPendingApproval(requestId: String, account: String) throws {
        let updated = try metadataIndex.updatePendingApprovalStatus(
            requestId: requestId,
            account: account,
            from: .pending,
            to: .rejected
        )

        guard updated > 0 else {
            throw ClawMailError.invalidParameter("Pending approval '\(requestId)' not found for account '\(account)'")
        }
    }

    // MARK: - Internal Helpers

    private func enforceGuardrails(
        account: String,
        recipients: [EmailAddress],
        heldRequest: PendingApprovalRequestEnvelope? = nil
    ) async throws {
        let result = try await guardrailEngine.checkSend(account: account, recipients: recipients)
        switch result {
        case .allowed: break
        case .blocked(let error): throw error
        case .pendingApproval(let emails):
            if let heldRequest {
                try metadataIndex.queuePendingApproval(request: heldRequest, emails: emails)
            }
            onPendingApproval?(account, emails)
            throw ClawMailError.recipientPendingApproval(emails: emails)
        }
    }

    func auditSuccess(
        interface: AgentInterface,
        operation: String,
        account: String,
        parameters: [String: AnyCodableValue],
        details: [String: AnyCodableValue]? = nil
    ) throws {
        try auditLog.log(entry: AuditEntry(
            interface: interface,
            operation: operation,
            account: account,
            parameters: parameters,
            result: .success,
            details: details
        ))
    }

    private func auditEvent(
        interface: AgentInterface,
        operation: String,
        account: String? = nil,
        parameters: [String: AnyCodableValue]? = nil,
        result: AuditResult = .success,
        details: [String: AnyCodableValue]? = nil
    ) {
        try? auditLog.log(entry: AuditEntry(
            interface: interface,
            operation: operation,
            account: account,
            parameters: parameters,
            result: result,
            details: details
        ))
    }

    func performInitialSyncIfNeeded(
        account: Account,
        runInitialSync: @escaping @Sendable (Int) async throws -> Void
    ) async throws {
        guard try !metadataIndex.hasSyncState(account: account.label) else {
            return
        }
        try await runInitialSync(config.initialSyncDays)
    }

    func syncSettingsSnapshot() async -> OrchestratorSyncSettingsSnapshot {
        let scheduler = await syncScheduler.snapshot()
        return OrchestratorSyncSettingsSnapshot(
            syncIntervalMinutes: config.syncIntervalMinutes,
            initialSyncDays: config.initialSyncDays,
            idleFolders: config.idleFolders,
            schedulerInterval: scheduler.interval,
            schedulerFolders: scheduler.folders,
            scheduledAccounts: scheduler.accountLabels
        )
    }

    private func connectAccount(_ account: Account) async throws {
        let credentials = try await credentialStore.credentialsFor(account: account)
        if let idx = config.accounts.firstIndex(where: { $0.label == account.label }) {
            config.accounts[idx].connectionStatus = .connecting
        }
        onConnectionStatusChanged?(account.label, .connecting)

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

        do {
            try await emailManager.connect()
        } catch {
            let message = Self.describe(error)
            if let idx = config.accounts.firstIndex(where: { $0.label == account.label }) {
                config.accounts[idx].connectionStatus = .error(message)
            }
            onConnectionStatusChanged?(account.label, .error(message))
            auditEvent(
                interface: .app,
                operation: "account.connect",
                account: account.label,
                parameters: ["email": .string(account.emailAddress)],
                result: .failure,
                details: ["error": .string(message)]
            )
            throw error
        }

        // Update account's connection status in config and notify
        if let idx = config.accounts.firstIndex(where: { $0.label == account.label }) {
            config.accounts[idx].connectionStatus = .connected
        }
        onConnectionStatusChanged?(account.label, .connected)
        auditEvent(
            interface: .app,
            operation: "account.connect",
            account: account.label,
            parameters: ["email": .string(account.emailAddress)]
        )

        var calMgr: CalendarManager? = nil
        var contactsMgr: ContactsManager? = nil
        var taskMgr: TaskManager? = nil

        if let caldavURL = account.caldavURL {
            let caldavClient = try CalDAVClient(
                baseURL: caldavURL,
                credential: credentials.calDAVCredential(username: account.emailAddress)
            )
            try await caldavClient.authenticate()
            calMgr = CalendarManager(client: caldavClient)
            taskMgr = TaskManager(client: caldavClient)
        }

        if let carddavURL = account.carddavURL {
            let carddavClient = try CardDAVClient(
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

        try await performInitialSyncIfNeeded(account: account) { days in
            try await syncEngine.initialSync(account: account, days: days)
        }

        let newMailCallback = onNewMail
        let errorCallback = onError
        let sEngine = syncEngine
        try await startIdleMonitor(
            idleMonitor,
            account: account,
            credential: imapCredential,
            syncEngine: sEngine,
            onNewMail: newMailCallback,
            onError: errorCallback
        )

        connections[account.label] = AccountConnection(
            emailManager: emailManager,
            calendarManager: calMgr,
            contactsManager: contactsMgr,
            taskManager: taskMgr,
            idleMonitor: idleMonitor,
            syncEngine: syncEngine
        )

        do {
            try await releaseReadyPendingApprovals(account: account.label)
        } catch {
            onError?(account.label, "Failed to release pending approvals: \(error)")
        }
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

    private func restartSyncScheduler() async {
        var engines: [String: SyncEngine] = [:]
        for (label, conn) in connections {
            engines[label] = conn.syncEngine
        }
        let folders = Self.normalizedIdleFolders(config.idleFolders)

        await syncScheduler.start(
            accounts: config.accounts.filter(\.isEnabled),
            syncEngines: engines,
            interval: TimeInterval(config.syncIntervalMinutes * 60),
            folders: folders
        )
    }

    private func restartIdleMonitoring() async throws {
        let accountsByLabel = Dictionary(uniqueKeysWithValues: config.accounts.map { ($0.label, $0) })

        for (label, connection) in connections {
            guard let account = accountsByLabel[label] else { continue }
            let credentials = try await credentialStore.credentialsFor(account: account)
            let imapCredential = credentials.imapCredential(username: account.emailAddress)
            await connection.idleMonitor.stop()
            try await startIdleMonitor(
                connection.idleMonitor,
                account: account,
                credential: imapCredential,
                syncEngine: connection.syncEngine,
                onNewMail: onNewMail,
                onError: onError
            )
        }
    }

    private func startIdleMonitor(
        _ idleMonitor: IMAPIdleMonitor,
        account: Account,
        credential: IMAPCredential,
        syncEngine: SyncEngine,
        onNewMail: (@Sendable (String, String) -> Void)?,
        onError: (@Sendable (String, String) -> Void)?
    ) async throws {
        let folders = Self.normalizedIdleFolders(config.idleFolders)
        try await idleMonitor.start(
            account: account,
            credential: credential,
            folders: folders,
            onNewMail: { [syncEngine, onNewMail, onError] accountLabel, folder in
                Task {
                    do {
                        try await syncEngine.handleNewMail(folder: folder)
                    } catch {
                        let msg = String(describing: error)
                        fputs("ClawMail: IDLE sync error for \(accountLabel)/\(folder): \(msg)\n", stderr)
                        onError?(accountLabel, msg)
                    }
                }
                onNewMail?(accountLabel, folder)
            }
        )
    }

    private static func normalizedIdleFolders(_ folders: [String]) -> [String] {
        let normalized = folders
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else { return ["INBOX"] }

        var seen = Set<String>()
        return normalized.filter { seen.insert($0).inserted }
    }

    private static func describe(_ error: Error) -> String {
        if let clawMailError = error as? ClawMailError {
            return clawMailError.message
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }

    private func releaseReadyPendingApprovals(account: String) async throws {
        let approvals = try metadataIndex.listPendingApprovals(account: account)
        for approval in approvals {
            guard try isPendingApprovalReady(approval) else { continue }
            try await releasePendingApproval(requestId: approval.requestId, account: account)
        }
    }

    private func releasePendingApproval(requestId: String, account: String) async throws {
        guard let request = try metadataIndex.pendingApprovalRequest(
            requestId: requestId,
            account: account,
            status: .pending
        ) else {
            throw ClawMailError.invalidParameter("Pending approval '\(requestId)' not found for account '\(account)'")
        }

        let updated = try metadataIndex.updatePendingApprovalStatus(
            requestId: requestId,
            account: account,
            from: .pending,
            to: .approved
        )

        guard updated > 0 else { return }

        do {
            _ = try await replayPendingApproval(request)
        } catch {
            _ = try? metadataIndex.updatePendingApprovalStatus(
                requestId: requestId,
                account: account,
                from: .approved,
                to: .pending
            )
            throw error
        }
    }

    private func isPendingApprovalReady(_ approval: PendingApproval) throws -> Bool {
        if !guardrailConfigRef.value.firstTimeRecipientApproval {
            return true
        }

        for email in approval.emails {
            guard try metadataIndex.isRecipientApproved(email: email, account: approval.accountLabel) else {
                return false
            }
        }
        return true
    }

    private func replayPendingApproval(_ request: PendingApprovalRequestEnvelope) async throws -> String {
        if let pendingApprovalReplayHandler {
            return try await pendingApprovalReplayHandler(request)
        }

        switch request.payload {
        case .send(let sendRequest):
            return try await sendMessage(sendRequest, interface: request.interface)
        case .reply(let replyRequest):
            return try await replyToMessage(replyRequest, interface: request.interface)
        case .forward(let forwardRequest):
            return try await forwardMessage(forwardRequest, interface: request.interface)
        }
    }
}

struct OrchestratorSyncSettingsSnapshot: Sendable, Equatable {
    let syncIntervalMinutes: Int
    let initialSyncDays: Int
    let idleFolders: [String]
    let schedulerInterval: TimeInterval
    let schedulerFolders: [String]
    let scheduledAccounts: [String]
}

// MARK: - Credential Conversion Helpers

extension Credentials {
    func imapCredential(username: String) -> IMAPCredential {
        switch self {
        case .password(let password):
            return .password(username: username, password: password)
        case .oauth2(let tokenProvider):
            return .oauth2(username: username, tokenProvider: tokenProvider)
        }
    }

    func calDAVCredential(username: String) -> CalDAVCredential {
        switch self {
        case .password(let password):
            return .password(username: username, password: password)
        case .oauth2(let tokenProvider):
            return .oauthToken(tokenProvider)
        }
    }

    func cardDAVCredential(username: String) -> CardDAVCredential {
        switch self {
        case .password(let password):
            return .password(username: username, password: password)
        case .oauth2(let tokenProvider):
            return .oauthToken(tokenProvider)
        }
    }
}
