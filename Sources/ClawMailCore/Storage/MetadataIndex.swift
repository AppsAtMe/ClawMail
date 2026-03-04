import Foundation
import GRDB

public final class MetadataIndex: Sendable {
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

            // When we have body text, clean up old FTS entry before replacing
            // the metadata row (INSERT OR REPLACE changes the rowid, orphaning old FTS)
            if bodyText != nil {
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
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM message_metadata WHERE id = ? AND account_label = ?",
                arguments: [id, account]
            )
            return row.map { try? Self.summaryFromRow($0) } ?? nil
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
            return rows.compactMap { try? Self.summaryFromRow($0) }
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
            var args: [DatabaseValueConvertible?] = [sanitizedQuery, account]

            if let folder = folder {
                sql += " AND m.folder = ?"
                args.append(folder)
            }

            sql += " ORDER BY m.date DESC LIMIT ? OFFSET ?"
            args.append(limit)
            args.append(offset)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)!)
            return rows.compactMap { try? Self.summaryFromRow($0) }
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

    // MARK: - Approved Recipients

    public func isRecipientApproved(email: String) throws -> Bool {
        try db.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM approved_recipients WHERE email = ?",
                arguments: [email]
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

    public func listApprovedRecipients(account: String? = nil) throws -> [(email: String, approvedAt: Date)] {
        try db.read { db in
            var sql = "SELECT email, approved_at FROM approved_recipients"
            var args: [DatabaseValueConvertible?] = []
            if let account = account {
                sql += " WHERE account_label = ?"
                args.append(account)
            }
            sql += " ORDER BY approved_at DESC"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)!)
            return rows.map { (email: $0["email"], approvedAt: $0["approved_at"]) }
        }
    }

    public func removeApprovedRecipient(email: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM approved_recipients WHERE email = ?",
                arguments: [email]
            )
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

    /// Sanitize a search query for FTS5. If the query contains unbalanced quotes
    /// or FTS5 operators that would cause a parse error, wrap it as a phrase search.
    static func sanitizeFTS5Query(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\"\"" }

        // Check for unbalanced double quotes
        let quoteCount = trimmed.filter { $0 == "\"" }.count
        if quoteCount % 2 != 0 {
            // Unbalanced quotes — escape the whole thing as a phrase
            let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        return trimmed
    }

    private static func summaryFromRow(_ row: Row) throws -> EmailSummary {
        let flagStrings = try JSONDecoder().decode([String].self, from: (row["flags_json"] as String).data(using: .utf8)!)
        let flags = Set(flagStrings.compactMap { EmailFlag(rawValue: $0) })

        return EmailSummary(
            id: row["id"],
            account: row["account_label"],
            folder: row["folder"],
            from: EmailAddress(name: row["sender_name"], email: row["sender_email"]),
            to: [],  // Simplified — full recipients available via recipients_json if needed
            cc: [],
            subject: row["subject"],
            date: row["date"],
            flags: flags,
            size: row["size"],
            hasAttachments: row["has_attachments"],
            uid: (row["uid"] as Int64?).map { UInt32($0) }
        )
    }
}
