import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Status Command

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show daemon status"
    )

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        await executeRPC(socketPath: socketPath, method: "status", params: nil, format: format)
    }
}
