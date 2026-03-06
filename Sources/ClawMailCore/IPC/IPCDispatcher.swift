import Foundation

/// Dispatches JSON-RPC 2.0 requests to the appropriate AccountOrchestrator methods.
public actor IPCDispatcher {

    private let orchestrator: AccountOrchestrator

    public init(orchestrator: AccountOrchestrator) {
        self.orchestrator = orchestrator
    }

    /// Parse and dispatch a raw JSON-RPC request, returning a response.
    public func dispatch(_ data: Data, interface: AgentInterface) async -> JSONRPCResponse {
        let request: JSONRPCRequest
        do {
            request = try decodeJSONRPC(JSONRPCRequest.self, from: data)
        } catch {
            return .error(id: nil, code: JSONRPCError.parseError, message: "Failed to parse JSON-RPC request")
        }

        do {
            let result = try await handleMethod(request.method, params: request.params ?? [:], interface: interface)
            return .success(id: request.id, result: result)
        } catch let error as ClawMailError {
            return JSONRPCResponse(id: request.id, error: .from(error))
        } catch {
            return .error(id: request.id, code: JSONRPCError.internalError, message: String(describing: error))
        }
    }

    // MARK: - Method Routing

    private func handleMethod(_ method: String, params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        switch method {
        // Email operations
        case "email.list": return try await handleEmailList(params)
        case "email.read": return try await handleEmailRead(params)
        case "email.send": return try await handleEmailSend(params, interface: interface)
        case "email.reply": return try await handleEmailReply(params, interface: interface)
        case "email.forward": return try await handleEmailForward(params, interface: interface)
        case "email.move": return try await handleEmailMove(params, interface: interface)
        case "email.delete": return try await handleEmailDelete(params, interface: interface)
        case "email.updateFlags": return try await handleEmailUpdateFlags(params, interface: interface)
        case "email.search": return try await handleEmailSearch(params)
        case "email.listFolders": return try await handleEmailListFolders(params)
        case "email.createFolder": return try await handleEmailCreateFolder(params, interface: interface)
        case "email.deleteFolder": return try await handleEmailDeleteFolder(params, interface: interface)
        case "email.downloadAttachment": return try await handleEmailDownloadAttachment(params)

        // Calendar operations
        case "calendar.listCalendars": return try await handleCalendarListCalendars(params)
        case "calendar.listEvents": return try await handleCalendarListEvents(params)
        case "calendar.createEvent": return try await handleCalendarCreateEvent(params, interface: interface)
        case "calendar.updateEvent": return try await handleCalendarUpdateEvent(params, interface: interface)
        case "calendar.deleteEvent": return try await handleCalendarDeleteEvent(params, interface: interface)

        // Contact operations
        case "contacts.listAddressBooks": return try await handleContactsListAddressBooks(params)
        case "contacts.list": return try await handleContactsList(params)
        case "contacts.create": return try await handleContactsCreate(params, interface: interface)
        case "contacts.update": return try await handleContactsUpdate(params, interface: interface)
        case "contacts.delete": return try await handleContactsDelete(params, interface: interface)

        // Task operations
        case "tasks.listTaskLists": return try await handleTasksListTaskLists(params)
        case "tasks.list": return try await handleTasksList(params)
        case "tasks.create": return try await handleTasksCreate(params, interface: interface)
        case "tasks.update": return try await handleTasksUpdate(params, interface: interface)
        case "tasks.delete": return try await handleTasksDelete(params, interface: interface)

        // Audit & status
        case "audit.list": return try await handleAuditList(params)
        case "accounts.list": return try await handleAccountsList(params)
        case "status": return try await handleStatus(params)

        // Approved recipients
        case "recipients.list": return try await handleRecipientsList(params)
        case "recipients.approve": return try await handleRecipientsApprove(params)
        case "recipients.remove": return try await handleRecipientsRemove(params)

        default:
            throw ClawMailError.invalidParameter("Unknown method: \(method)")
        }
    }

    // MARK: - Parameter Helpers

    private func requireString(_ params: [String: AnyCodableValue], _ key: String) throws -> String {
        guard case .string(let value) = params[key] else {
            throw ClawMailError.invalidParameter("Missing required parameter: \(key)")
        }
        return value
    }

    private func optionalString(_ params: [String: AnyCodableValue], _ key: String) -> String? {
        guard case .string(let value) = params[key] else { return nil }
        return value
    }

    private func optionalInt(_ params: [String: AnyCodableValue], _ key: String) -> Int? {
        guard case .int(let value) = params[key] else { return nil }
        return value
    }

    private func optionalBool(_ params: [String: AnyCodableValue], _ key: String) -> Bool? {
        guard case .bool(let value) = params[key] else { return nil }
        return value
    }

    private func requireEmailAddresses(_ params: [String: AnyCodableValue], _ key: String) throws -> [EmailAddress] {
        guard case .array(let arr) = params[key] else {
            throw ClawMailError.invalidParameter("Missing required parameter: \(key)")
        }
        return arr.compactMap { item -> EmailAddress? in
            if case .string(let email) = item {
                return EmailAddress(email: email)
            }
            if case .dictionary(let dict) = item,
               case .string(let email) = dict["email"] {
                let name: String? = {
                    if case .string(let n) = dict["name"] { return n }
                    return nil
                }()
                return EmailAddress(name: name, email: email)
            }
            return nil
        }
    }

    private func optionalEmailAddresses(_ params: [String: AnyCodableValue], _ key: String) -> [EmailAddress]? {
        guard case .array(let arr) = params[key] else { return nil }
        let result = arr.compactMap { item -> EmailAddress? in
            if case .string(let email) = item {
                return EmailAddress(email: email)
            }
            if case .dictionary(let dict) = item,
               case .string(let email) = dict["email"] {
                let name: String? = {
                    if case .string(let n) = dict["name"] { return n }
                    return nil
                }()
                return EmailAddress(name: name, email: email)
            }
            return nil
        }
        return result.isEmpty ? nil : result
    }

    private func encodableToValue<T: Encodable>(_ value: T) throws -> AnyCodableValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(AnyCodableValue.self, from: data)
    }

    // MARK: - Email Handlers

    private func handleEmailList(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let folder = optionalString(params, "folder") ?? "INBOX"
        let limit = optionalInt(params, "limit") ?? 50
        let offset = optionalInt(params, "offset") ?? 0
        let messages = try await orchestrator.listMessages(account: account, folder: folder, limit: limit, offset: offset)
        return try encodableToValue(messages)
    }

    private func handleEmailRead(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        let message = try await orchestrator.readMessage(account: account, id: id)
        return try encodableToValue(message)
    }

    private func handleEmailSend(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let to = try requireEmailAddresses(params, "to")
        let subject = try requireString(params, "subject")
        let body = try requireString(params, "body")
        let cc = optionalEmailAddresses(params, "cc")
        let bcc = optionalEmailAddresses(params, "bcc")
        let bodyHtml = optionalString(params, "bodyHtml")

        var attachments: [String]? = nil
        if case .array(let arr) = params["attachments"] {
            attachments = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        }

        let request = SendEmailRequest(
            account: account, to: to, cc: cc, bcc: bcc,
            subject: subject, body: body, bodyHtml: bodyHtml,
            attachments: attachments
        )
        let messageId = try await orchestrator.sendMessage(request, interface: interface)
        return .dictionary(["messageId": .string(messageId)])
    }

    private func handleEmailReply(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let originalMessageId = try requireString(params, "originalMessageId")
        let body = try requireString(params, "body")
        let replyAll = optionalBool(params, "replyAll") ?? false

        let request = ReplyEmailRequest(
            account: account, originalMessageId: originalMessageId,
            body: body, replyAll: replyAll
        )
        let messageId = try await orchestrator.replyToMessage(request, interface: interface)
        return .dictionary(["messageId": .string(messageId)])
    }

    private func handleEmailForward(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let originalMessageId = try requireString(params, "originalMessageId")
        let to = try requireEmailAddresses(params, "to")
        let body = optionalString(params, "body")

        let request = ForwardEmailRequest(
            account: account, originalMessageId: originalMessageId,
            to: to, body: body
        )
        let messageId = try await orchestrator.forwardMessage(request, interface: interface)
        return .dictionary(["messageId": .string(messageId)])
    }

    private func handleEmailMove(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        let folder = try requireString(params, "folder")
        try await orchestrator.moveMessage(account: account, id: id, to: folder, interface: interface)
        return .dictionary(["success": .bool(true)])
    }

    private func handleEmailDelete(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        let permanent = optionalBool(params, "permanent") ?? false
        try await orchestrator.deleteMessage(account: account, id: id, permanent: permanent, interface: interface)
        return .dictionary(["success": .bool(true)])
    }

    private func handleEmailUpdateFlags(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        var addFlags: [EmailFlag] = []
        var removeFlags: [EmailFlag] = []
        if case .array(let arr) = params["add"] {
            addFlags = arr.compactMap { if case .string(let s) = $0 { return EmailFlag(rawValue: s) } else { return nil } }
        }
        if case .array(let arr) = params["remove"] {
            removeFlags = arr.compactMap { if case .string(let s) = $0 { return EmailFlag(rawValue: s) } else { return nil } }
        }
        let updated = try await orchestrator.updateFlags(account: account, id: id, add: addFlags, remove: removeFlags, interface: interface)
        return try encodableToValue(updated)
    }

    private func handleEmailSearch(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let query = try requireString(params, "query")
        let folder = optionalString(params, "folder")
        let limit = optionalInt(params, "limit") ?? 50
        let offset = optionalInt(params, "offset") ?? 0
        let messages = try await orchestrator.searchMessages(account: account, query: query, folder: folder, limit: limit, offset: offset)
        return try encodableToValue(messages)
    }

    private func handleEmailListFolders(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let folders = try await orchestrator.listFolders(account: account)
        return try encodableToValue(folders)
    }

    private func handleEmailCreateFolder(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let name = try requireString(params, "name")
        let parent = optionalString(params, "parent")
        try await orchestrator.createFolder(account: account, name: name, parent: parent, interface: interface)
        return .dictionary(["success": .bool(true)])
    }

    private func handleEmailDeleteFolder(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let path = try requireString(params, "path")
        try await orchestrator.deleteFolder(account: account, path: path, interface: interface)
        return .dictionary(["success": .bool(true)])
    }

    private func handleEmailDownloadAttachment(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let messageId = try requireString(params, "messageId")
        let filename = try requireString(params, "filename")
        let path = try requireString(params, "path")
        let result = try await orchestrator.downloadAttachment(account: account, messageId: messageId, filename: filename, path: path)
        return .dictionary(["path": .string(result.path), "size": .int(result.size)])
    }

    // MARK: - Calendar Handlers

    private func handleCalendarListCalendars(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let calendars = try await orchestrator.listCalendars(account: account)
        return try encodableToValue(calendars)
    }

    private func handleCalendarListEvents(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let fromStr = try requireString(params, "from")
        let toStr = try requireString(params, "to")
        let calendar = optionalString(params, "calendar")

        let formatter = ISO8601DateFormatter()
        guard let from = formatter.date(from: fromStr),
              let to = formatter.date(from: toStr) else {
            throw ClawMailError.invalidParameter("Invalid date format. Use ISO 8601.")
        }
        let events = try await orchestrator.listEvents(account: account, from: from, to: to, calendar: calendar)
        return try encodableToValue(events)
    }

    private func handleCalendarCreateEvent(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let request = try decodeFromParams(CreateEventRequest.self, params: params)
        let event = try await orchestrator.createEvent(account: account, request, interface: interface)
        return try encodableToValue(event)
    }

    private func handleCalendarUpdateEvent(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        let request = try decodeFromParams(UpdateEventRequest.self, params: params)
        let event = try await orchestrator.updateEvent(account: account, id: id, request, interface: interface)
        return try encodableToValue(event)
    }

    private func handleCalendarDeleteEvent(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        try await orchestrator.deleteEvent(account: account, id: id, interface: interface)
        return .dictionary(["success": .bool(true)])
    }

    // MARK: - Contacts Handlers

    private func handleContactsListAddressBooks(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let books = try await orchestrator.listAddressBooks(account: account)
        return try encodableToValue(books)
    }

    private func handleContactsList(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let addressBook = optionalString(params, "addressBook")
        let query = optionalString(params, "query")
        let limit = optionalInt(params, "limit") ?? 100
        let offset = optionalInt(params, "offset") ?? 0
        let contacts = try await orchestrator.listContacts(account: account, addressBook: addressBook, query: query, limit: limit, offset: offset)
        return try encodableToValue(contacts)
    }

    private func handleContactsCreate(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let request = try decodeFromParams(CreateContactRequest.self, params: params)
        let contact = try await orchestrator.createContact(account: account, request, interface: interface)
        return try encodableToValue(contact)
    }

    private func handleContactsUpdate(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        let request = try decodeFromParams(UpdateContactRequest.self, params: params)
        let contact = try await orchestrator.updateContact(account: account, id: id, request, interface: interface)
        return try encodableToValue(contact)
    }

    private func handleContactsDelete(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        try await orchestrator.deleteContact(account: account, id: id, interface: interface)
        return .dictionary(["success": .bool(true)])
    }

    // MARK: - Tasks Handlers

    private func handleTasksListTaskLists(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let lists = try await orchestrator.listTaskLists(account: account)
        return try encodableToValue(lists)
    }

    private func handleTasksList(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let taskList = optionalString(params, "taskList")
        let includeCompleted = optionalBool(params, "includeCompleted") ?? false
        let tasks = try await orchestrator.listTasks(account: account, taskList: taskList, includeCompleted: includeCompleted)
        return try encodableToValue(tasks)
    }

    private func handleTasksCreate(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let request = try decodeFromParams(CreateTaskRequest.self, params: params)
        let task = try await orchestrator.createTask(account: account, request, interface: interface)
        return try encodableToValue(task)
    }

    private func handleTasksUpdate(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        let request = try decodeFromParams(UpdateTaskRequest.self, params: params)
        let task = try await orchestrator.updateTask(account: account, id: id, request, interface: interface)
        return try encodableToValue(task)
    }

    private func handleTasksDelete(_ params: [String: AnyCodableValue], interface: AgentInterface) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let id = try requireString(params, "id")
        try await orchestrator.deleteTask(account: account, id: id, interface: interface)
        return .dictionary(["success": .bool(true)])
    }

    // MARK: - Audit & Status Handlers

    private func handleAuditList(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = optionalString(params, "account")
        let limit = optionalInt(params, "limit") ?? 100
        let offset = optionalInt(params, "offset") ?? 0
        let entries = try await orchestrator.getAuditLog(account: account, limit: limit, offset: offset)
        return try encodableToValue(entries)
    }

    private func handleAccountsList(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let accounts = await orchestrator.listAccounts()
        return try encodableToValue(accounts)
    }

    private func handleStatus(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let accounts = await orchestrator.listAccounts()
        let isAgentConnected = await orchestrator.isAgentConnected
        return .dictionary([
            "status": .string("running"),
            "accounts": .int(accounts.count),
            "agentConnected": .bool(isAgentConnected),
        ])
    }

    // MARK: - Recipients Handlers

    private func handleRecipientsList(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = optionalString(params, "account")
        let recipients = try await orchestrator.listApprovedRecipients(account: account)
        let arr: [AnyCodableValue] = recipients.map { r in
            .dictionary([
                "email": .string(r.email),
                "account": .string(r.accountLabel),
                "approvedAt": .string(ISO8601DateFormatter().string(from: r.approvedAt)),
            ])
        }
        return .array(arr)
    }

    private func handleRecipientsApprove(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        if case .array(let emails) = params["emails"] {
            let emailStrings = emails.compactMap { if case .string(let s) = $0 { return s } else { return nil as String? } }
            try await orchestrator.approvePendingRecipients(emails: emailStrings, account: account)
        } else if case .string(let email) = params["email"] {
            try await orchestrator.approveRecipient(email: email, account: account)
        }
        return .dictionary(["success": .bool(true)])
    }

    private func handleRecipientsRemove(_ params: [String: AnyCodableValue]) async throws -> AnyCodableValue {
        let account = try requireString(params, "account")
        let email = try requireString(params, "email")
        try await orchestrator.removeApprovedRecipient(email: email, account: account)
        return .dictionary(["success": .bool(true)])
    }

    // MARK: - Helpers

    /// Decode a Codable type from the params dictionary by re-encoding to JSON first.
    private func decodeFromParams<T: Decodable>(_ type: T.Type, params: [String: AnyCodableValue]) throws -> T {
        let data = try JSONEncoder().encode(params)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
