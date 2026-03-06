import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Recipients Command Group

struct RecipientsGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recipients",
        abstract: "Approved recipients management",
        subcommands: [
            RecipientsList.self,
            RecipientsPending.self,
            RecipientsApprove.self,
            RecipientsReject.self,
            RecipientsRemove.self,
        ]
    )
}

// MARK: - recipients list

struct RecipientsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List approved recipients"
    )

    @Option(name: .long, help: "Filter by account label")
    var account: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [:]
        if let account { params["account"] = .string(account) }

        let finalParams: [String: AnyCodableValue]? = params.isEmpty ? nil : params
        await executeRPC(socketPath: socketPath, method: "recipients.list", params: finalParams, format: format)
    }
}

// MARK: - recipients pending

struct RecipientsPending: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pending",
        abstract: "List held send approvals"
    )

    @Option(name: .long, help: "Filter by account label")
    var account: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [:]
        if let account { params["account"] = .string(account) }

        let finalParams: [String: AnyCodableValue]? = params.isEmpty ? nil : params
        await executeRPC(socketPath: socketPath, method: "recipients.pending", params: finalParams, format: format)
    }
}

// MARK: - recipients approve

struct RecipientsApprove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "approve",
        abstract: "Approve recipient email addresses"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("request-id"), help: "Release a held send request by request ID")
    var requestId: String?

    @Argument(parsing: .captureForPassthrough, help: "Email addresses to approve")
    var emails: [String]

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue]

        if let requestId {
            guard emails.isEmpty else {
                throw ValidationError("Provide either --request-id or email arguments, not both.")
            }
            params = [
                "account": .string(account),
                "requestId": .string(requestId),
            ]
        } else {
            guard !emails.isEmpty else {
                throw ValidationError("Provide at least one email address or use --request-id.")
            }
            params = [
                "account": .string(account),
                "emails": .array(emails.map { .string($0) }),
            ]
        }

        await executeRPC(socketPath: socketPath, method: "recipients.approve", params: params, format: format)
    }
}

// MARK: - recipients reject

struct RecipientsReject: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reject",
        abstract: "Reject a held send request"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("request-id"), help: "Held send request ID")
    var requestId: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
            "requestId": .string(requestId),
        ]
        await executeRPC(socketPath: socketPath, method: "recipients.reject", params: params, format: format)
    }
}

// MARK: - recipients remove

struct RecipientsRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove an approved recipient"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Email address to remove")
    var email: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
            "email": .string(email),
        ]
        await executeRPC(socketPath: socketPath, method: "recipients.remove", params: params, format: format)
    }
}
