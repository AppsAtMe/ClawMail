import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Accounts Command Group

struct AccountsGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accounts",
        abstract: "Account management",
        subcommands: [
            AccountsList.self,
        ]
    )
}

// MARK: - accounts list

struct AccountsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List configured accounts"
    )

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        await executeRPC(socketPath: socketPath, method: "accounts.list", params: nil, format: format)
    }
}
