import Foundation
import GRDB

public final class DatabaseManager: Sendable {
    /// Underlying database writer — DatabasePool for production, DatabaseQueue for in-memory tests.
    private let dbWriter: any DatabaseWriter

    public static let defaultDatabaseURL: URL = {
        AppConfig.defaultDirectoryURL.appendingPathComponent("metadata.sqlite")
    }()

    public init(path: String? = nil) throws {
        let dbPath = path ?? Self.defaultDatabaseURL.path
        let directory = URL(fileURLWithPath: dbPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: dbPath)
        self.dbWriter = pool
        try Self.runMigrations(pool)
    }

    /// For in-memory testing. Uses DatabaseQueue since in-memory SQLite doesn't support WAL mode
    /// (which DatabasePool requires).
    public init(inMemory: Bool) throws {
        let queue = try DatabaseQueue()
        self.dbWriter = queue
        try Self.runMigrations(queue)
    }

    // MARK: - Read/Write helpers

    public func read<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) throws -> T {
        try dbWriter.read(block)
    }

    public func write<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) throws -> T {
        try dbWriter.write(block)
    }

    // MARK: - Migrations

    private static func runMigrations(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        // Migration 1: Message metadata
        migrator.registerMigration("createMessageMetadata") { db in
            try db.create(table: "message_metadata") { t in
                t.column("id", .text).primaryKey()
                t.column("account_label", .text).notNull()
                t.column("folder", .text).notNull()
                t.column("sender_name", .text)
                t.column("sender_email", .text).notNull()
                t.column("recipients_json", .text).notNull()
                t.column("subject", .text)
                t.column("date", .datetime).notNull()
                t.column("flags_json", .text).notNull()
                t.column("size", .integer)
                t.column("has_attachments", .boolean).notNull().defaults(to: false)
                t.column("uid", .integer)
                t.uniqueKey(["account_label", "folder", "uid"])
            }
            try db.create(
                index: "idx_msg_account_folder",
                on: "message_metadata",
                columns: ["account_label", "folder"]
            )
            try db.create(
                index: "idx_msg_date",
                on: "message_metadata",
                columns: ["date"]
            )
            try db.create(
                index: "idx_msg_sender",
                on: "message_metadata",
                columns: ["sender_email"]
            )
        }

        // Migration 2: FTS5 full-text search
        migrator.registerMigration("createFTSIndex") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE message_fts USING fts5(
                    subject,
                    body_text,
                    sender_email,
                    sender_name
                )
            """)
        }

        // Migration 3: Audit log
        migrator.registerMigration("createAuditLog") { db in
            try db.create(table: "audit_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("interface", .text).notNull()
                t.column("operation", .text).notNull()
                t.column("account_label", .text)
                t.column("parameters_json", .text)
                t.column("result", .text).notNull()
                t.column("details_json", .text)
            }
            try db.create(index: "idx_audit_timestamp", on: "audit_log", columns: ["timestamp"])
            try db.create(index: "idx_audit_account", on: "audit_log", columns: ["account_label"])
            try db.create(index: "idx_audit_operation", on: "audit_log", columns: ["operation"])
        }

        // Migration 4: Sync state
        migrator.registerMigration("createSyncState") { db in
            try db.create(table: "sync_state") { t in
                t.column("account_label", .text).notNull()
                t.column("folder", .text).notNull()
                t.column("uid_validity", .integer)
                t.column("highest_mod_seq", .integer)
                t.column("last_sync", .datetime)
                t.primaryKey(["account_label", "folder"])
            }
        }

        // Migration 5: Approved recipients
        migrator.registerMigration("createApprovedRecipients") { db in
            try db.create(table: "approved_recipients") { t in
                t.column("email", .text).primaryKey()
                t.column("approved_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("account_label", .text).notNull()
            }
        }

        // Migration 6: Pending approvals
        migrator.registerMigration("createPendingApprovals") { db in
            try db.create(table: "pending_approvals") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("email", .text).notNull()
                t.column("account_label", .text).notNull()
                t.column("send_request_json", .text).notNull()
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("status", .text).notNull().defaults(to: "pending")
            }
        }

        try migrator.migrate(writer)
    }
}
