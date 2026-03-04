import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Audit Command Group

struct AuditGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Audit log operations",
        subcommands: [
            AuditList.self,
        ]
    )
}

// MARK: - audit list

struct AuditList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List audit log entries"
    )

    @Option(name: .long, help: "Filter by account label")
    var account: String?

    @Option(name: .long, help: "Maximum number of entries")
    var limit: Int?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [:]
        if let account { params["account"] = .string(account) }
        if let limit { params["limit"] = .int(limit) }

        let finalParams: [String: AnyCodableValue]? = params.isEmpty ? nil : params
        await executeRPC(socketPath: socketPath, method: "audit.list", params: finalParams, format: format)
    }
}
