import Foundation
import GRDB

public final class AuditLog: Sendable {
    private let db: DatabaseManager

    public init(db: DatabaseManager) {
        self.db = db
    }

    // MARK: - Log Entry

    public func log(entry: AuditEntry) throws {
        try db.write { db in
            let paramsJSON: String? = if let params = entry.parameters {
                String(data: try JSONEncoder().encode(params), encoding: .utf8)
            } else {
                nil
            }
            let detailsJSON: String? = if let details = entry.details {
                String(data: try JSONEncoder().encode(details), encoding: .utf8)
            } else {
                nil
            }

            try db.execute(
                sql: """
                    INSERT INTO audit_log (timestamp, interface, operation, account_label, parameters_json, result, details_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    entry.timestamp,
                    entry.interface.rawValue,
                    entry.operation,
                    entry.account,
                    paramsJSON,
                    entry.result.rawValue,
                    detailsJSON,
                ]
            )
        }
    }

    // MARK: - Query

    public func list(
        limit: Int = 50,
        offset: Int = 0,
        account: String? = nil,
        operation: String? = nil,
        from: Date? = nil,
        to: Date? = nil
    ) throws -> [AuditEntry] {
        try db.read { db in
            var conditions: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let account = account {
                conditions.append("account_label = ?")
                args.append(account)
            }
            if let operation = operation {
                conditions.append("operation = ?")
                args.append(operation)
            }
            if let from = from {
                conditions.append("timestamp >= ?")
                args.append(from)
            }
            if let to = to {
                conditions.append("timestamp <= ?")
                args.append(to)
            }

            var sql = "SELECT * FROM audit_log"
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }
            sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
            args.append(limit)
            args.append(offset)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)!)
            return rows.compactMap { Self.entryFromRow($0) }
        }
    }

    public func count(account: String? = nil, operation: String? = nil) throws -> Int {
        try db.read { db in
            var conditions: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let account = account {
                conditions.append("account_label = ?")
                args.append(account)
            }
            if let operation = operation {
                conditions.append("operation = ?")
                args.append(operation)
            }

            var sql = "SELECT COUNT(*) FROM audit_log"
            if !conditions.isEmpty {
                sql += " WHERE " + conditions.joined(separator: " AND ")
            }

            return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(args)!) ?? 0
        }
    }

    /// Count sends within a time window (for rate limiting)
    public func countSends(account: String, since: Date) throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM audit_log
                    WHERE account_label = ? AND operation = 'email.send' AND result = 'success' AND timestamp >= ?
                """,
                arguments: [account, since]
            ) ?? 0
        }
    }

    // MARK: - Cleanup

    public func purgeOlderThan(days: Int) throws {
        try db.write { db in
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            try db.execute(
                sql: "DELETE FROM audit_log WHERE timestamp < ?",
                arguments: [cutoff]
            )
        }
    }

    // MARK: - Row Mapping

    private static func entryFromRow(_ row: Row) -> AuditEntry? {
        guard let interfaceStr: String = row["interface"],
              let interface = AgentInterface(rawValue: interfaceStr),
              let resultStr: String = row["result"],
              let result = AuditResult(rawValue: resultStr) else {
            return nil
        }

        let params: [String: AnyCodableValue]? = {
            guard let json: String = row["parameters_json"],
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)
        }()

        let details: [String: AnyCodableValue]? = {
            guard let json: String = row["details_json"],
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)
        }()

        return AuditEntry(
            id: row["id"],
            timestamp: row["timestamp"],
            interface: interface,
            operation: row["operation"],
            account: row["account_label"],
            parameters: params,
            result: result,
            details: details
        )
    }
}
