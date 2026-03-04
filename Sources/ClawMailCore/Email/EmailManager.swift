import Foundation

/// High-level email management actor that coordinates IMAP, SMTP, the metadata
/// index, and email body cleaning.  This is the primary abstraction that agent
/// interfaces (CLI / MCP / REST) interact with for all email operations.
public actor EmailManager {

    // MARK: - Dependencies

    private let account: Account
    private let imapClient: IMAPClient
    private let smtpClient: SMTPClient
    private let metadataIndex: MetadataIndex
    private let cleaner = EmailCleaner()
    private let searchEngine = SearchEngine()

    private var _status: ConnectionStatus = .disconnected

    public var connectionStatus: ConnectionStatus { _status }

    // MARK: - Init

    public init(account: Account, metadataIndex: MetadataIndex) {
        self.account = account
        self.metadataIndex = metadataIndex

        let imapCredential: IMAPCredential
        switch account.authMethod {
        case .password:
            imapCredential = .password(username: account.emailAddress, password: "")
        case .oauth2:
            imapCredential = .oauth2(username: account.emailAddress, accessToken: "")
        }

        self.imapClient = IMAPClient(
            host: account.imapHost,
            port: account.imapPort,
            security: account.imapSecurity,
            credential: imapCredential
        )

        let smtpCreds: Credentials = .password("")
        self.smtpClient = SMTPClient(
            host: account.smtpHost,
            port: account.smtpPort,
            security: account.smtpSecurity,
            credentials: smtpCreds,
            senderEmail: account.emailAddress
        )
    }

    /// Direct dependency injection for testing or advanced configuration.
    public init(
        account: Account,
        imapClient: IMAPClient,
        smtpClient: SMTPClient,
        metadataIndex: MetadataIndex
    ) {
        self.account = account
        self.imapClient = imapClient
        self.smtpClient = smtpClient
        self.metadataIndex = metadataIndex
    }

    // MARK: - Connection Lifecycle

    public func connect() async throws {
        _status = .connecting
        do {
            try await imapClient.connect()
            try await imapClient.authenticate()
            try await smtpClient.connect()
            _status = .connected
        } catch {
            _status = .error(error.localizedDescription)
            throw error
        }
    }

    public func disconnect() async {
        try? await smtpClient.disconnect()
        await imapClient.disconnect()
        _status = .disconnected
    }

    // MARK: - List Messages

    public func listMessages(
        folder: String = "INBOX",
        limit: Int = 50,
        offset: Int = 0,
        sort: SortOrder = .dateDescending
    ) async throws -> [EmailSummary] {
        let localResults = try metadataIndex.listMessages(
            account: account.label,
            folder: folder,
            limit: limit,
            offset: offset,
            sort: sort
        )

        if !localResults.isEmpty {
            return localResults
        }

        try await refreshFolder(folder)
        return try metadataIndex.listMessages(
            account: account.label,
            folder: folder,
            limit: limit,
            offset: offset,
            sort: sort
        )
    }

    // MARK: - Read Message

    public func readMessage(id: String) async throws -> EmailMessage {
        guard let summary = try metadataIndex.getMessage(id: id, account: account.label) else {
            throw ClawMailError.messageNotFound(id)
        }

        guard let uid = UInt32(id.components(separatedBy: "/").last ?? "") else {
            throw ClawMailError.messageNotFound(id)
        }
        let folder = summary.folder
        let body = try await imapClient.fetchMessageBody(folder: folder, uid: uid)

        let parts = MIMEParser.parseMIME(body.rawData)

        var plainText = ""
        var htmlBody: String?
        var attachments: [EmailAttachment] = []

        for (index, part) in parts.enumerated() {
            let ct = part.contentType.lowercased()
            if ct.hasPrefix("text/plain") && part.disposition != "attachment" {
                plainText += part.decodedText ?? ""
            } else if ct.hasPrefix("text/html") && part.disposition != "attachment" {
                htmlBody = part.decodedText
            } else if part.disposition == "attachment" || part.filename != nil {
                attachments.append(EmailAttachment(
                    filename: part.filename ?? "unnamed",
                    mimeType: part.contentType,
                    size: part.body.count,
                    section: String(index + 1)
                ))
            }
        }

        if plainText.isEmpty, let html = htmlBody {
            plainText = cleaner.extractPlainTextFromHTML(html)
        }

        let cleanedText = cleaner.clean(plainText: plainText)

        // Fetch headers for messageId / inReplyTo / references
        let headers = try await imapClient.fetchMessageHeaders(folder: folder, uid: uid)

        return EmailMessage(
            id: summary.id,
            account: account.label,
            folder: folder,
            from: summary.from,
            to: summary.to,
            cc: summary.cc,
            subject: summary.subject,
            date: summary.date,
            flags: summary.flags,
            bodyPlain: cleanedText,
            bodyPlainRaw: plainText,
            bodyHtml: htmlBody,
            attachments: attachments,
            headers: headers
        )
    }

    // MARK: - Send Message

    public func sendMessage(_ request: SendEmailRequest) async throws -> String {
        var outgoingAttachments: [OutgoingAttachment] = []
        if let paths = request.attachments {
            for path in paths {
                _ = try Self.validateAttachmentSourcePath(path)
                let attachment = try OutgoingAttachment.fromFile(path: path)
                outgoingAttachments.append(attachment)
            }
        }

        let outgoing = OutgoingEmail(
            from: EmailAddress(name: account.displayName, email: account.emailAddress),
            to: request.to,
            cc: request.cc ?? [],
            bcc: request.bcc ?? [],
            subject: request.subject,
            bodyPlain: request.body,
            bodyHtml: request.bodyHtml,
            attachments: outgoingAttachments
        )

        return try await smtpClient.send(message: outgoing)
    }

    // MARK: - Reply

    public func replyToMessage(_ request: ReplyEmailRequest) async throws -> String {
        let original = try await readMessage(id: request.originalMessageId)

        let inReplyTo = original.headers["Message-ID"]
        var references = original.headers["References"] ?? ""
        if let mid = inReplyTo {
            if !references.isEmpty { references += " " }
            references += mid
        }

        var toRecipients: [EmailAddress]
        if request.replyAll {
            toRecipients = [original.from]
            toRecipients.append(contentsOf: original.to.filter { $0.email != account.emailAddress })
        } else {
            toRecipients = [original.from]
        }

        let ccRecipients: [EmailAddress] = request.replyAll
            ? original.cc.filter { $0.email != account.emailAddress }
            : []

        let subject: String
        if let subj = original.subject, subj.hasPrefix("Re: ") {
            subject = subj
        } else {
            subject = "Re: \(original.subject ?? "")"
        }

        let outgoing = OutgoingEmail(
            from: EmailAddress(name: account.displayName, email: account.emailAddress),
            to: toRecipients,
            cc: ccRecipients,
            subject: subject,
            bodyPlain: request.body,
            bodyHtml: request.bodyHtml,
            inReplyTo: inReplyTo,
            references: references
        )

        return try await smtpClient.send(message: outgoing)
    }

    // MARK: - Forward

    public func forwardMessage(
        messageId: String,
        to: [EmailAddress],
        body: String?,
        attachments: [String]?
    ) async throws -> String {
        let original = try await readMessage(id: messageId)

        let subject: String
        if let subj = original.subject, subj.hasPrefix("Fwd: ") {
            subject = subj
        } else {
            subject = "Fwd: \(original.subject ?? "")"
        }

        var bodyText = body ?? ""
        bodyText += "\n\n---------- Forwarded message ----------\n"
        bodyText += "From: \(original.from.displayString)\n"
        bodyText += "Date: \(original.date)\n"
        bodyText += "Subject: \(original.subject ?? "")\n"
        bodyText += "To: \(original.to.map(\.displayString).joined(separator: ", "))\n\n"
        bodyText += original.bodyPlain ?? ""

        var outgoingAttachments: [OutgoingAttachment] = []
        if let paths = attachments {
            for path in paths {
                _ = try Self.validateAttachmentSourcePath(path)
                let attachment = try OutgoingAttachment.fromFile(path: path)
                outgoingAttachments.append(attachment)
            }
        }

        // Forward original attachments
        if !original.attachments.isEmpty {
            let (_, uid) = try resolveMessageUid(messageId)
            for att in original.attachments {
                let section = att.section ?? "1"
                let data = try await imapClient.fetchAttachment(
                    folder: original.folder,
                    uid: uid,
                    section: section
                )
                outgoingAttachments.append(OutgoingAttachment(
                    data: data,
                    filename: att.filename,
                    mimeType: att.mimeType
                ))
            }
        }

        let outgoing = OutgoingEmail(
            from: EmailAddress(name: account.displayName, email: account.emailAddress),
            to: to,
            subject: subject,
            bodyPlain: bodyText,
            attachments: outgoingAttachments
        )

        return try await smtpClient.send(message: outgoing)
    }

    // MARK: - Move / Delete / Flags

    public func moveMessage(id: String, to destination: String) async throws {
        let (folder, uid) = try resolveMessageUid(id)
        try await imapClient.moveMessage(uid: uid, from: folder, to: destination)

        if var summary = try metadataIndex.getMessage(id: id, account: account.label) {
            try metadataIndex.deleteMessage(id: id, account: account.label)
            summary.folder = destination
            try metadataIndex.upsertMessage(summary)
        }
    }

    public func deleteMessage(id: String, permanent: Bool = false) async throws {
        let (folder, uid) = try resolveMessageUid(id)
        try await imapClient.deleteMessage(uid: uid, folder: folder, permanent: permanent)
        try metadataIndex.deleteMessage(id: id, account: account.label)
    }

    public func updateFlags(id: String, add: [EmailFlag] = [], remove: [EmailFlag] = []) async throws {
        let (folder, uid) = try resolveMessageUid(id)
        try await imapClient.updateFlags(uid: uid, folder: folder, add: add, remove: remove)

        if var summary = try metadataIndex.getMessage(id: id, account: account.label) {
            for flag in add { summary.flags.insert(flag) }
            for flag in remove { summary.flags.remove(flag) }
            try metadataIndex.upsertMessage(summary)
        }
    }

    // MARK: - Search

    public func searchMessages(
        query: String,
        folder: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [EmailSummary] {
        let parsed = searchEngine.parseQuery(query)

        if let ftsQuery = parsed.ftsQuery {
            let localResults = try metadataIndex.search(
                account: account.label,
                query: ftsQuery,
                folder: parsed.folder ?? folder,
                limit: limit,
                offset: offset
            )
            if !localResults.isEmpty {
                return localResults
            }
        }

        let searchFolder = parsed.folder ?? folder ?? "INBOX"
        let criteria = buildIMAPCriteria(from: parsed)
        let uids = try await imapClient.searchMessages(folder: searchFolder, criteria: criteria)

        guard !uids.isEmpty else { return [] }

        let startUid = uids.min() ?? 1
        let endUid = uids.max() ?? startUid
        let range = UIDRange(start: startUid, end: endUid)
        let summaries = try await imapClient.fetchMessageSummaries(folder: searchFolder, range: range)

        let uidSet = Set(uids)
        let filtered = summaries.filter { uidSet.contains($0.uid) }
        return filtered.prefix(limit).map { convertToSummary($0, folder: searchFolder) }
    }

    // MARK: - Folders

    public func listFolders() async throws -> [FolderInfo] {
        let imapFolders = try await imapClient.listFolders()
        return imapFolders.filter(\.isSelectable).map { folder in
            FolderInfo(
                name: folder.name.components(separatedBy: "/").last ?? folder.name,
                path: folder.name
            )
        }
    }

    public func createFolder(name: String, parent: String? = nil) async throws {
        let path = parent.map { "\($0)/\(name)" } ?? name
        try await imapClient.createFolder(path)
    }

    public func deleteFolder(path: String) async throws {
        try await imapClient.deleteFolder(path)
    }

    // MARK: - Attachments

    /// Validate that a path is safe for writing (no path traversal, stays within allowed directories).
    private static func validateDestinationPath(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardized
        let resolved = url.path

        // Must be an absolute path
        guard resolved.hasPrefix("/") else {
            throw ClawMailError.invalidParameter("Destination path must be absolute")
        }

        // Block writing outside user-accessible directories
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let tempDir = NSTemporaryDirectory()
        let allowed = [
            home + "/Downloads",
            home + "/Documents",
            home + "/Desktop",
            tempDir,
        ]

        guard allowed.contains(where: { resolved.hasPrefix($0) }) else {
            throw ClawMailError.invalidParameter(
                "Destination path must be within ~/Downloads, ~/Documents, ~/Desktop, or temp directory"
            )
        }

        // Reject if the resolved path still contains ".." (shouldn't after standardized, but defense in depth)
        guard !resolved.contains("..") else {
            throw ClawMailError.invalidParameter("Path traversal detected in destination path")
        }

        return url
    }

    /// Validate that a source path is safe for reading as an attachment.
    static func validateAttachmentSourcePath(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardized
        let resolved = url.path

        guard resolved.hasPrefix("/") else {
            throw ClawMailError.invalidParameter("Attachment path must be absolute")
        }

        // Block reading from sensitive directories
        let blocked = [
            "/etc/", "/var/", "/private/", "/System/", "/Library/",
            "/usr/", "/bin/", "/sbin/", "/opt/",
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sensitiveHome = [
            home + "/.ssh", home + "/.gnupg", home + "/.config",
            home + "/.aws", home + "/Library/Keychains",
            home + "/Library/Application Support/ClawMail",
        ]

        let allBlocked = blocked + sensitiveHome
        guard !allBlocked.contains(where: { resolved.hasPrefix($0) }) else {
            throw ClawMailError.invalidParameter("Access to this path is restricted for security")
        }

        guard !resolved.contains("..") else {
            throw ClawMailError.invalidParameter("Path traversal detected in attachment path")
        }

        return url
    }

    public func downloadAttachment(
        messageId: String,
        filename: String,
        destinationPath: String
    ) async throws -> (path: String, size: Int) {
        let url = try Self.validateDestinationPath(destinationPath)

        let original = try await readMessage(id: messageId)
        let (_, uid) = try resolveMessageUid(messageId)

        guard let att = original.attachments.first(where: { $0.filename == filename }) else {
            throw ClawMailError.messageNotFound("Attachment '\(filename)' not found")
        }

        let section = att.section ?? "1"
        let data = try await imapClient.fetchAttachment(
            folder: original.folder,
            uid: uid,
            section: section
        )

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)

        return (path: url.path, size: data.count)
    }

    // MARK: - Sync

    private func refreshFolder(_ folder: String) async throws {
        let syncState = try metadataIndex.getSyncState(account: account.label, folder: folder)

        // If we have CONDSTORE modseq, use incremental sync
        if let state = syncState, let modSeq = state.highestModSeq, modSeq > 0 {
            let changed = try await imapClient.fetchChangedSince(folder: folder, modSeq: modSeq)
            for iSummary in changed {
                let emailSummary = convertToSummary(iSummary, folder: folder)
                try metadataIndex.upsertMessage(emailSummary)
            }
        } else {
            // Full fetch
            let range = UIDRange(start: 1)
            let summaries = try await imapClient.fetchMessageSummaries(folder: folder, range: range)
            for iSummary in summaries {
                let emailSummary = convertToSummary(iSummary, folder: folder)
                try metadataIndex.upsertMessage(emailSummary)
            }
        }

        // Update sync state with current uidValidity and modSeq
        let uidValidity = try await imapClient.getUIDValidity(folder: folder)
        let highestModSeq = try await imapClient.getHighestModSeq(folder: folder)
        let state = SyncState(
            accountLabel: account.label,
            folder: folder,
            uidValidity: uidValidity,
            highestModSeq: highestModSeq,
            lastSync: Date()
        )
        try metadataIndex.updateSyncState(state)
    }

    // MARK: - Helpers

    private func resolveMessageUid(_ id: String) throws -> (folder: String, uid: UInt32) {
        guard let summary = try metadataIndex.getMessage(id: id, account: account.label) else {
            throw ClawMailError.messageNotFound(id)
        }
        guard let uid = UInt32(id.components(separatedBy: "/").last ?? "") else {
            throw ClawMailError.messageNotFound(id)
        }
        return (summary.folder, uid)
    }

    private func convertToSummary(_ imap: IMAPMessageSummary, folder: String) -> EmailSummary {
        let id = "\(account.label)/\(folder)/\(imap.uid)"
        return EmailSummary(
            id: id,
            account: account.label,
            folder: folder,
            from: imap.envelope.from.first ?? EmailAddress(email: "unknown@unknown.com"),
            to: imap.envelope.to,
            cc: imap.envelope.cc,
            subject: imap.envelope.subject ?? "(No Subject)",
            date: imap.envelope.date ?? Date(),
            flags: imap.flags,
            size: imap.size,
            hasAttachments: imap.hasAttachments,
            uid: imap.uid,
            messageId: imap.envelope.messageId,
            inReplyTo: imap.envelope.inReplyTo
        )
    }

    private func buildIMAPCriteria(from query: SearchQuery) -> IMAPSearchCriteria {
        var criteria: [IMAPSearchCriteria] = []

        if let from = query.from { criteria.append(.from(from)) }
        if let to = query.to { criteria.append(.to(to)) }
        if let subject = query.subject { criteria.append(.subject(subject)) }
        if let body = query.body { criteria.append(.body(body)) }
        if query.isUnread == true { criteria.append(.unseen) }
        if query.isRead == true { criteria.append(.seen) }
        if query.isFlagged == true { criteria.append(.flagged) }
        if let before = query.before { criteria.append(.before(before)) }
        if let after = query.after { criteria.append(.since(after)) }
        if let freeText = query.freeText { criteria.append(.body(freeText)) }

        if criteria.isEmpty { return .all }
        if criteria.count == 1 { return criteria[0] }

        var result = criteria[0]
        for i in 1..<criteria.count {
            result = .and(result, criteria[i])
        }
        return result
    }
}
