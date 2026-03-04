import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Contacts Command Group

struct ContactsGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contacts",
        abstract: "Contacts operations",
        subcommands: [
            ContactsAddressBooks.self,
            ContactsList.self,
            ContactsCreate.self,
            ContactsUpdate.self,
            ContactsDelete.self,
        ]
    )
}

// MARK: - contacts address-books

struct ContactsAddressBooks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "address-books",
        abstract: "List available address books"
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
        await executeRPC(socketPath: socketPath, method: "contacts.listAddressBooks", params: params, format: format)
    }
}

// MARK: - contacts list

struct ContactsList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List contacts"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("address-book"), help: "Address book name filter")
    var addressBook: String?

    @Option(name: .long, help: "Search query")
    var query: String?

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
        if let addressBook { params["addressBook"] = .string(addressBook) }
        if let query { params["query"] = .string(query) }
        if let limit { params["limit"] = .int(limit) }
        if let offset { params["offset"] = .int(offset) }

        await executeRPC(socketPath: socketPath, method: "contacts.list", params: params, format: format)
    }
}

// MARK: - contacts create

struct ContactsCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new contact"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("address-book"), help: "Address book name")
    var addressBook: String

    @Option(name: .customLong("display-name"), help: "Display name")
    var displayName: String

    @Option(name: .customLong("first-name"), help: "First name")
    var firstName: String?

    @Option(name: .customLong("last-name"), help: "Last name")
    var lastName: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Email addresses (format: type:address, e.g. work:john@example.com)")
    var emails: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Phone numbers (format: type:number, e.g. mobile:+1234567890)")
    var phones: [String] = []

    @Option(name: .long, help: "Organization name")
    var organization: String?

    @Option(name: .long, help: "Job title")
    var title: String?

    @Option(name: .long, help: "Notes")
    var notes: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "addressBook": .string(addressBook),
            "displayName": .string(displayName),
        ]
        if let firstName { params["firstName"] = .string(firstName) }
        if let lastName { params["lastName"] = .string(lastName) }
        if !emails.isEmpty {
            params["emails"] = .array(emails.map { parseTypedValue($0, typeKey: "type", valueKey: "address") })
        }
        if !phones.isEmpty {
            params["phones"] = .array(phones.map { parseTypedValue($0, typeKey: "type", valueKey: "number") })
        }
        if let organization { params["organization"] = .string(organization) }
        if let title { params["title"] = .string(title) }
        if let notes { params["notes"] = .string(notes) }

        await executeRPC(socketPath: socketPath, method: "contacts.create", params: params, format: format)
    }
}

// MARK: - contacts update

struct ContactsUpdate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a contact"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Contact ID")
    var id: String

    @Option(name: .customLong("display-name"), help: "New display name")
    var displayName: String?

    @Option(name: .customLong("first-name"), help: "New first name")
    var firstName: String?

    @Option(name: .customLong("last-name"), help: "New last name")
    var lastName: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Updated emails (format: type:address)")
    var emails: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Updated phones (format: type:number)")
    var phones: [String] = []

    @Option(name: .long, help: "New organization")
    var organization: String?

    @Option(name: .long, help: "New job title")
    var title: String?

    @Option(name: .long, help: "New notes")
    var notes: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "id": .string(id),
        ]
        if let displayName { params["displayName"] = .string(displayName) }
        if let firstName { params["firstName"] = .string(firstName) }
        if let lastName { params["lastName"] = .string(lastName) }
        if !emails.isEmpty {
            params["emails"] = .array(emails.map { parseTypedValue($0, typeKey: "type", valueKey: "address") })
        }
        if !phones.isEmpty {
            params["phones"] = .array(phones.map { parseTypedValue($0, typeKey: "type", valueKey: "number") })
        }
        if let organization { params["organization"] = .string(organization) }
        if let title { params["title"] = .string(title) }
        if let notes { params["notes"] = .string(notes) }

        await executeRPC(socketPath: socketPath, method: "contacts.update", params: params, format: format)
    }
}

// MARK: - contacts delete

struct ContactsDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a contact"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Contact ID")
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
        await executeRPC(socketPath: socketPath, method: "contacts.delete", params: params, format: format)
    }
}

// MARK: - Helper

/// Parse a "type:value" string into a dictionary AnyCodableValue.
/// e.g. "work:john@example.com" -> {"type": "work", "address": "john@example.com"}
private func parseTypedValue(_ input: String, typeKey: String, valueKey: String) -> AnyCodableValue {
    let parts = input.split(separator: ":", maxSplits: 1)
    if parts.count == 2 {
        return .dictionary([
            typeKey: .string(String(parts[0])),
            valueKey: .string(String(parts[1])),
        ])
    }
    // If no type prefix, use "other" as default type
    return .dictionary([
        typeKey: .string("other"),
        valueKey: .string(input),
    ])
}
