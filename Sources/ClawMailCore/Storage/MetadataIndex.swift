import Foundation
import GRDB

public final class MetadataIndex: Sendable {
    struct PendingApprovalRecord: Sendable {
        let rowID: Int64
        let email: String
        let accountLabel: String
        let createdAt: Date
        let status: PendingApprovalStatus
        let request: PendingApprovalRequestEnvelope
    }

    private let db: DatabaseManager

    public init(db: DatabaseManager) {
        self.db = db
    }

    // MARK: - Message CRUD

    public func upsertMessage(_ summary: EmailSummary, bodyText: String? = nil) throws {
        try db.write { db in
            let recipientsJSON = try JSONEncoder().encode(
                summary.to.map { ["name": $0.name ?? "", "email": $0.email, "type": "to"] } +
                summary.cc.map { ["name": $0.name ?? "", "email": $0.email, "type": "cc"] }
            )
            let flagsJSON = try JSONEncoder().encode(summary.flags.map(\.rawValue))
            let recipientsStr = String(data: recipientsJSON, encoding: .utf8) ?? "[]"
            let flagsStr = String(data: flagsJSON, encoding: .utf8) ?? "[]"

            // Always clean up old FTS entry before INSERT OR REPLACE, since
            // REPLACE changes the rowid, orphaning any existing FTS entry.
            let oldRowid = try Int64.fetchOne(
                db,
                sql: "SELECT rowid FROM message_metadata WHERE id = ? AND account_label = ?",
                arguments: [summary.id, summary.account]
            )
            if let oldRowid = oldRowid {
                try db.execute(
                    sql: "DELETE FROM message_fts WHERE rowid = ?",
                    arguments: [oldRowid]
                )
            }

            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO message_metadata
                    (id, account_label, folder, sender_name, sender_email, recipients_json,
                     subject, date, flags_json, size, has_attachments, uid)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    summary.id,
                    summary.account,
                    summary.folder,
                    summary.from.name,
                    summary.from.email,
                    recipientsStr,
                    summary.subject,
                    summary.date,
                    flagsStr,
                    summary.size,
                    summary.hasAttachments,
                    summary.uid.map { Int64($0) },
                ]
            )

            // Insert new FTS entry with the new rowid
            if let bodyText = bodyText {
                let rowid = db.lastInsertedRowID
                try db.execute(
                    sql: """
                        INSERT INTO message_fts(rowid, subject, body_text, sender_email, sender_name)
                        VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [rowid, summary.subject, bodyText, summary.from.email, summary.from.name]
                )
            }
        }
    }

    public func deleteMessage(id: String, account: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM message_metadata WHERE id = ? AND account_label = ?",
                arguments: [id, account]
            )
        }
    }

    public func getMessage(id: String, account: String) throws -> EmailSummary? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM message_metadata WHERE id = ? AND account_label = ?",
                arguments: [id, account]
            ) else { return nil }
            return try Self.summaryFromRow(row)
        }
    }

    public func listMessages(
        account: String,
        folder: String,
        limit: Int = 20,
        offset: Int = 0,
        sort: SortOrder = .dateDescending
    ) throws -> [EmailSummary] {
        try db.read { db in
            let orderClause = sort == .dateDescending ? "date DESC" : "date ASC"
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM message_metadata
                    WHERE account_label = ? AND folder = ?
                    ORDER BY \(orderClause)
                    LIMIT ? OFFSET ?
                """,
                arguments: [account, folder, limit, offset]
            )
            return try rows.map { try Self.summaryFromRow($0) }
        }
    }

    // MARK: - Search

    public func search(
        account: String,
        query: String,
        folder: String? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) throws -> [EmailSummary] {
        // Sanitize the FTS5 query: wrap in double quotes to treat as phrase search
        // if it contains FTS5 operators or unbalanced quotes that would cause errors.
        let sanitizedQuery = Self.sanitizeFTS5Query(query)

        return try db.read { db in
            var sql = """
                SELECT m.* FROM message_metadata m
                JOIN message_fts f ON m.rowid = f.rowid
                WHERE f.message_fts MATCH ? AND m.account_label = ?
            """
            var args: StatementArguments = [sanitizedQuery, account]

            if let folder = folder {
                sql += " AND m.folder = ?"
                args += [folder]
            }

            sql += " ORDER BY m.date DESC LIMIT ? OFFSET ?"
            args += [limit, offset]

            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return try rows.map { try Self.summaryFromRow($0) }
        }
    }

    // MARK: - Folder Info

    public func getFolderStats(account: String) throws -> [FolderInfo] {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT folder,
                           COUNT(*) as total,
                           SUM(CASE WHEN flags_json NOT LIKE '%seen%' THEN 1 ELSE 0 END) as unread
                    FROM message_metadata
                    WHERE account_label = ?
                    GROUP BY folder
                """,
                arguments: [account]
            )
            return rows.map { row in
                FolderInfo(
                    name: row["folder"],
                    path: row["folder"],
                    unreadCount: row["unread"],
                    totalCount: row["total"]
                )
            }
        }
    }

    // MARK: - Sync State

    public func getSyncState(account: String, folder: String) throws -> SyncState? {
        try db.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM sync_state WHERE account_label = ? AND folder = ?",
                arguments: [account, folder]
            )
            guard let row = row else { return nil }
            return SyncState(
                accountLabel: row["account_label"],
                folder: row["folder"],
                uidValidity: (row["uid_validity"] as Int64?).map { UInt32($0) },
                highestModSeq: (row["highest_mod_seq"] as Int64?).map { UInt64($0) },
                lastSync: row["last_sync"]
            )
        }
    }

    public func updateSyncState(_ state: SyncState) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO sync_state
                    (account_label, folder, uid_validity, highest_mod_seq, last_sync)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    state.accountLabel,
                    state.folder,
                    state.uidValidity.map { Int64($0) },
                    state.highestModSeq.map { Int64($0) },
                    state.lastSync,
                ]
            )
        }
    }

    public func hasSyncState(account: String) throws -> Bool {
        try db.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sync_state WHERE account_label = ?",
                arguments: [account]
            )
            return (count ?? 0) > 0
        }
    }

    // MARK: - Approved Recipients

    public func isRecipientApproved(email: String, account: String) throws -> Bool {
        try db.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM approved_recipients WHERE email = ? AND account_label = ?",
                arguments: [email, account]
            )
            return (count ?? 0) > 0
        }
    }

    public func approveRecipient(email: String, account: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO approved_recipients (email, account_label) VALUES (?, ?)",
                arguments: [email, account]
            )
        }
    }

    public func listApprovedRecipients(account: String? = nil) throws -> [ApprovedRecipient] {
        try db.read { db in
            var sql = "SELECT email, account_label, approved_at FROM approved_recipients"
            var args: StatementArguments = []
            if let account = account {
                sql += " WHERE account_label = ?"
                args += [account]
            }
            sql += " ORDER BY approved_at DESC, account_label ASC, email ASC"
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.map {
                ApprovedRecipient(
                    email: $0["email"],
                    accountLabel: $0["account_label"],
                    approvedAt: $0["approved_at"]
                )
            }
        }
    }

    public func removeApprovedRecipient(email: String, account: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM approved_recipients WHERE email = ? AND account_label = ?",
                arguments: [email, account]
            )
        }
    }

    // MARK: - Pending Approvals

    func queuePendingApproval(
        request: PendingApprovalRequestEnvelope,
        emails: [String]
    ) throws {
        let uniqueEmails = Array(Set(emails)).sorted()
        guard !uniqueEmails.isEmpty else { return }

        let requestJSON = try Self.encodePendingApprovalRequest(request)

        try db.write { db in
            for email in uniqueEmails {
                let existing = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM pending_approvals
                        WHERE email = ? AND account_label = ? AND send_request_json = ? AND status = ?
                    """,
                    arguments: [
                        email,
                        request.accountLabel,
                        requestJSON,
                        PendingApprovalStatus.pending.rawValue,
                    ]
                ) ?? 0

                guard existing == 0 else { continue }

                try db.execute(
                    sql: """
                        INSERT INTO pending_approvals (email, account_label, send_request_json, status)
                        VALUES (?, ?, ?, ?)
                    """,
                    arguments: [
                        email,
                        request.accountLabel,
                        requestJSON,
                        PendingApprovalStatus.pending.rawValue,
                    ]
                )
            }
        }
    }

    public func listPendingApprovals(
        account: String? = nil,
        status: PendingApprovalStatus = .pending
    ) throws -> [PendingApproval] {
        let records = try pendingApprovalRecords(account: account, status: status)
        let grouped = Dictionary(grouping: records, by: \.request.requestId)

        return grouped.values.compactMap { records in
            guard let first = records.first else { return nil }
            return PendingApproval(
                requestId: first.request.requestId,
                accountLabel: first.accountLabel,
                emails: records.map(\.email).sorted(),
                createdAt: records.map(\.createdAt).min() ?? first.createdAt,
                status: first.status,
                operation: first.request.operation,
                subject: first.request.subject
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.requestId < rhs.requestId
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func pendingApprovalRecords(
        account: String? = nil,
        status: PendingApprovalStatus? = .pending
    ) throws -> [PendingApprovalRecord] {
        try db.read { db in
            var sql = """
                SELECT id, email, account_label, send_request_json, created_at, status
                FROM pending_approvals
            """
            var conditions: [String] = []
            var args: StatementArguments = []

            if let account {
                conditions.append("account_label = ?")
                args += [account]
            }

            if let status {
                conditions.append("status = ?")
                args += [status.rawValue]
            }

            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            sql += " ORDER BY created_at DESC, id DESC"

            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return try rows.map { row in
                let statusRaw: String = row["status"]
                let rowStatus = PendingApprovalStatus(rawValue: statusRaw) ?? .pending
                let requestJSON: String = row["send_request_json"]

                return PendingApprovalRecord(
                    rowID: row["id"],
                    email: row["email"],
                    accountLabel: row["account_label"],
                    createdAt: row["created_at"],
                    status: rowStatus,
                    request: try Self.decodePendingApprovalRequest(from: requestJSON)
                )
            }
        }
    }

    func pendingApprovalRequest(
        requestId: String,
        account: String,
        status: PendingApprovalStatus? = .pending
    ) throws -> PendingApprovalRequestEnvelope? {
        try pendingApprovalRecords(account: account, status: status)
            .first { $0.request.requestId == requestId }?
            .request
    }

    @discardableResult
    func updatePendingApprovalStatus(
        requestId: String,
        account: String,
        from currentStatus: PendingApprovalStatus? = nil,
        to newStatus: PendingApprovalStatus
    ) throws -> Int {
        let recordIDs = try pendingApprovalRecords(account: account, status: currentStatus)
            .filter { $0.request.requestId == requestId }
            .map(\.rowID)

        guard !recordIDs.isEmpty else { return 0 }

        return try db.write { db in
            let placeholders = Self.sqlPlaceholders(count: recordIDs.count)
            var args: StatementArguments = [newStatus.rawValue]
            for recordID in recordIDs {
                args += [recordID]
            }
            try db.execute(
                sql: "UPDATE pending_approvals SET status = ? WHERE id IN (\(placeholders))",
                arguments: args
            )
            return Int(db.changesCount)
        }
    }

    // MARK: - Cleanup

    public func purgeAccount(label: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM message_metadata WHERE account_label = ?", arguments: [label])
            try db.execute(sql: "DELETE FROM sync_state WHERE account_label = ?", arguments: [label])
            try db.execute(sql: "DELETE FROM approved_recipients WHERE account_label = ?", arguments: [label])
            try db.execute(sql: "DELETE FROM pending_approvals WHERE account_label = ?", arguments: [label])
        }
    }

    // MARK: - Row Mapping

    /// Sanitize a search query for FTS5. Always escapes the input as a phrase
    /// search to prevent FTS5 query injection (operator injection, cross-column search).
    /// Internal callers that need FTS5 operators (like SearchEngine.ftsQuery) construct
    /// their own queries with per-term escaping before reaching this layer.
    static func sanitizeFTS5Query(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\"\"" }

        // Always wrap as a phrase search: double any internal quotes and wrap in quotes.
        // This prevents FTS5 operators (AND, OR, NOT, NEAR, column filters, prefix *)
        // from being interpreted, ensuring the query is treated as a literal phrase.
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func summaryFromRow(_ row: Row) throws -> EmailSummary {
        let flagsStr: String = row["flags_json"] ?? "[]"
        let flagsData = Data(flagsStr.utf8)
        let flagStrings = try JSONDecoder().decode([String].self, from: flagsData)
        let flags = Set(flagStrings.compactMap { EmailFlag(rawValue: $0) })

        let recipientsStr: String = row["recipients_json"] ?? "[]"
        let recipientDicts = (try? JSONDecoder().decode([[String: String]].self, from: Data(recipientsStr.utf8))) ?? []
        let toRecipients = recipientDicts.filter { $0["type"] == "to" }
            .map { EmailAddress(name: $0["name"], email: $0["email"] ?? "") }
        let ccRecipients = recipientDicts.filter { $0["type"] == "cc" }
            .map { EmailAddress(name: $0["name"], email: $0["email"] ?? "") }

        return EmailSummary(
            id: row["id"],
            account: row["account_label"],
            folder: row["folder"],
            from: EmailAddress(name: row["sender_name"], email: row["sender_email"]),
            to: toRecipients,
            cc: ccRecipients,
            subject: row["subject"],
            date: row["date"],
            flags: flags,
            size: row["size"],
            hasAttachments: row["has_attachments"],
            uid: (row["uid"] as Int64?).map { UInt32($0) }
        )
    }

    private static func encodePendingApprovalRequest(_ request: PendingApprovalRequestEnvelope) throws -> String {
        let data = try JSONEncoder().encode(request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ClawMailError.serverError("Failed to serialize pending approval request")
        }
        return json
    }

    private static func decodePendingApprovalRequest(from json: String) throws -> PendingApprovalRequestEnvelope {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(PendingApprovalRequestEnvelope.self, from: data)
    }

    private static func sqlPlaceholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
