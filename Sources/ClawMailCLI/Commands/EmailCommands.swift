import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Email Command Group

struct EmailGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "email",
        abstract: "Email operations",
        subcommands: [
            EmailList.self,
            EmailRead.self,
            EmailSend.self,
            EmailReply.self,
            EmailForward.self,
            EmailMove.self,
            EmailDelete.self,
            EmailFlag.self,
            EmailSearch.self,
            EmailFolders.self,
            EmailCreateFolder.self,
            EmailDeleteFolder.self,
            EmailDownloadAttachment.self,
        ]
    )
}

// MARK: - email list

struct EmailList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List emails in a folder"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, help: "Folder path (default: INBOX)")
    var folder: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int?

    @Option(name: .long, help: "Offset for pagination")
    var offset: Int?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
        ]
        if let folder { params["folder"] = .string(folder) }
        if let limit { params["limit"] = .int(limit) }
        if let offset { params["offset"] = .int(offset) }

        await executeRPC(socketPath: socketPath, method: "email.list", params: params, format: format)
    }
}

// MARK: - email read

struct EmailRead: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a specific email"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Message ID")
    var id: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
            "id": .string(id),
        ]
        await executeRPC(socketPath: socketPath, method: "email.read", params: params, format: format)
    }
}

// MARK: - email send

struct EmailSend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a new email"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, parsing: .upToNextOption, help: "Recipient email addresses")
    var to: [String]

    @Option(name: .long, help: "Subject line")
    var subject: String

    @Option(name: .long, help: "Plain text body")
    var body: String

    @Option(name: .long, parsing: .upToNextOption, help: "CC recipients")
    var cc: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "BCC recipients")
    var bcc: [String] = []

    @Option(name: .long, help: "HTML body")
    var bodyHtml: String?

    @Option(name: .long, parsing: .upToNextOption, help: "File paths to attach")
    var attach: [String] = []

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let toRecipients: [AnyCodableValue] = to.map { email in
            .dictionary(["email": .string(email)])
        }

        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "to": .array(toRecipients),
            "subject": .string(subject),
            "body": .string(body),
        ]

        if !cc.isEmpty {
            params["cc"] = .array(cc.map { .dictionary(["email": .string($0)]) })
        }
        if !bcc.isEmpty {
            params["bcc"] = .array(bcc.map { .dictionary(["email": .string($0)]) })
        }
        if let bodyHtml { params["bodyHtml"] = .string(bodyHtml) }
        if !attach.isEmpty {
            params["attachments"] = .array(attach.map { .string($0) })
        }

        await executeRPC(socketPath: socketPath, method: "email.send", params: params, format: format)
    }
}

// MARK: - email reply

struct EmailReply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Reply to an email"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("message-id"), help: "Original message ID")
    var originalMessageId: String

    @Option(name: .long, help: "Reply body")
    var body: String

    @Flag(name: .customLong("reply-all"), help: "Reply to all recipients")
    var replyAll: Bool = false

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "originalMessageId": .string(originalMessageId),
            "body": .string(body),
        ]
        if replyAll { params["replyAll"] = .bool(true) }

        await executeRPC(socketPath: socketPath, method: "email.reply", params: params, format: format)
    }
}

// MARK: - email forward

struct EmailForward: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forward",
        abstract: "Forward an email"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("message-id"), help: "Original message ID")
    var originalMessageId: String

    @Option(name: .long, parsing: .upToNextOption, help: "Recipient email addresses")
    var to: [String]

    @Option(name: .long, help: "Additional body text")
    var body: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let toRecipients: [AnyCodableValue] = to.map { email in
            .dictionary(["email": .string(email)])
        }

        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "originalMessageId": .string(originalMessageId),
            "to": .array(toRecipients),
        ]
        if let body { params["body"] = .string(body) }

        await executeRPC(socketPath: socketPath, method: "email.forward", params: params, format: format)
    }
}

// MARK: - email move

struct EmailMove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move an email to a different folder"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Message ID")
    var id: String

    @Option(name: .long, help: "Destination folder path")
    var folder: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
            "id": .string(id),
            "folder": .string(folder),
        ]
        await executeRPC(socketPath: socketPath, method: "email.move", params: params, format: format)
    }
}

// MARK: - email delete

struct EmailDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an email"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Message ID")
    var id: String

    @Flag(name: .long, help: "Permanently delete (skip trash)")
    var permanent: Bool = false

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "id": .string(id),
        ]
        if permanent { params["permanent"] = .bool(true) }

        await executeRPC(socketPath: socketPath, method: "email.delete", params: params, format: format)
    }
}

// MARK: - email flag

struct EmailFlag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flag",
        abstract: "Update email flags"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Message ID")
    var id: String

    @Option(name: .long, parsing: .upToNextOption, help: "Flags to add (seen, flagged, answered, draft)")
    var add: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Flags to remove")
    var remove: [String] = []

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "id": .string(id),
        ]
        if !add.isEmpty {
            params["add"] = .array(add.map { .string($0) })
        }
        if !remove.isEmpty {
            params["remove"] = .array(remove.map { .string($0) })
        }

        await executeRPC(socketPath: socketPath, method: "email.updateFlags", params: params, format: format)
    }
}

// MARK: - email search

struct EmailSearch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search emails"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Search query")
    var query: String

    @Option(name: .long, help: "Folder to search in")
    var folder: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int?

    @Option(name: .long, help: "Offset for pagination")
    var offset: Int?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "query": .string(query),
        ]
        if let folder { params["folder"] = .string(folder) }
        if let limit { params["limit"] = .int(limit) }
        if let offset { params["offset"] = .int(offset) }

        await executeRPC(socketPath: socketPath, method: "email.search", params: params, format: format)
    }
}

// MARK: - email folders

struct EmailFolders: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folders",
        abstract: "List email folders"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
        ]
        await executeRPC(socketPath: socketPath, method: "email.listFolders", params: params, format: format)
    }
}

// MARK: - email create-folder

struct EmailCreateFolder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-folder",
        abstract: "Create a new email folder"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, help: "Folder name")
    var name: String

    @Option(name: .long, help: "Parent folder path")
    var parent: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "name": .string(name),
        ]
        if let parent { params["parent"] = .string(parent) }

        await executeRPC(socketPath: socketPath, method: "email.createFolder", params: params, format: format)
    }
}

// MARK: - email delete-folder

struct EmailDeleteFolder: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-folder",
        abstract: "Delete an email folder"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, help: "Folder path to delete")
    var path: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
            "path": .string(path),
        ]
        await executeRPC(socketPath: socketPath, method: "email.deleteFolder", params: params, format: format)
    }
}

// MARK: - email download-attachment

struct EmailDownloadAttachment: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download-attachment",
        abstract: "Download an email attachment"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("message-id"), help: "Message ID")
    var messageId: String

    @Option(name: .long, help: "Attachment filename")
    var filename: String

    @Option(name: .long, help: "Destination file path")
    var path: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
            "messageId": .string(messageId),
            "filename": .string(filename),
            "path": .string(path),
        ]
        await executeRPC(socketPath: socketPath, method: "email.downloadAttachment", params: params, format: format)
    }
}
