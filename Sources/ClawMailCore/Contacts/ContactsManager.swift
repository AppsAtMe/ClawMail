import Foundation

// MARK: - ContactsManager

/// High-level actor that provides agent-facing contact operations.
///
/// Bridges between the agent interface (using `Contact` model objects)
/// and the underlying `CardDAVClient` (which speaks vCard/WebDAV).
public actor ContactsManager {

    // MARK: - Properties

    private let client: CardDAVClient

    // MARK: - Initialization

    public init(client: CardDAVClient) {
        self.client = client
    }

    // MARK: - Address Book Operations

    /// List all address books for the account.
    public func listAddressBooks() async throws -> [AddressBook] {
        let carddavBooks = try await client.listAddressBooks()
        return carddavBooks.map { AddressBook(name: $0.displayName) }
    }

    // MARK: - Contact Operations

    /// List contacts, optionally filtered by address book, query text, with pagination.
    public func listContacts(
        addressBook: String? = nil,
        query: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> [Contact] {
        let allBooks = try await client.listAddressBooks()

        let targetBooks: [CardDAVAddressBook]
        if let bookName = addressBook {
            targetBooks = allBooks.filter { $0.displayName == bookName }
            if targetBooks.isEmpty {
                throw ClawMailError.invalidParameter("Address book '\(bookName)' not found")
            }
        } else {
            targetBooks = allBooks
        }

        var allContacts: [Contact] = []

        for book in targetBooks {
            let vcardStrings = try await client.getContacts(addressBook: book.href, query: query)
            for vcardString in vcardStrings {
                let parsedContacts = VCardParser.parseContacts(from: vcardString)
                for parsed in parsedContacts {
                    let contact = contactModel(from: parsed, addressBookName: book.displayName)
                    allContacts.append(contact)
                }
            }
        }

        // Sort by display name
        allContacts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        // Apply pagination
        let startIndex = min(offset, allContacts.count)
        let endIndex = min(startIndex + limit, allContacts.count)

        if startIndex >= allContacts.count {
            return []
        }

        return Array(allContacts[startIndex..<endIndex])
    }

    /// Create a new contact.
    public func createContact(_ request: CreateContactRequest) async throws -> Contact {
        let books = try await client.listAddressBooks()
        guard let book = books.first(where: { $0.displayName == request.addressBook }) else {
            throw ClawMailError.invalidParameter("Address book '\(request.addressBook)' not found")
        }

        let uid = UUID().uuidString
        let emails: [(type: String, address: String)] = (request.emails ?? []).map { ($0.type, $0.address) }
        let phones: [(type: String, number: String)] = (request.phones ?? []).map { ($0.type, $0.number) }

        let vcard = VCardParser.buildVCard(
            uid: uid,
            formattedName: request.displayName,
            firstName: request.firstName,
            lastName: request.lastName,
            emails: emails,
            phones: phones,
            organization: request.organization,
            title: request.title,
            notes: request.notes
        )

        _ = try await client.createContact(addressBook: book.href, vcard: vcard)

        return Contact(
            id: uid,
            addressBook: request.addressBook,
            displayName: request.displayName,
            firstName: request.firstName,
            lastName: request.lastName,
            emails: request.emails ?? [],
            phones: request.phones ?? [],
            organization: request.organization,
            title: request.title,
            notes: request.notes
        )
    }

    /// Update an existing contact by ID (UID).
    public func updateContact(id: String, _ request: UpdateContactRequest) async throws -> Contact {
        // Find the address book containing this contact
        let books = try await client.listAddressBooks()

        var foundBook: CardDAVAddressBook?
        var foundVCardString: String?

        for book in books {
            let vcardStrings = try await client.getContacts(addressBook: book.href)
            for vcs in vcardStrings {
                if let uid = VCardParser.extractUID(from: vcs), uid == id {
                    foundBook = book
                    foundVCardString = vcs
                    break
                }
            }
            if foundBook != nil { break }
        }

        guard let book = foundBook, let existingVCard = foundVCardString else {
            throw ClawMailError.invalidParameter("Contact with ID '\(id)' not found")
        }

        // Parse existing contact and apply updates
        let existingContacts = VCardParser.parseContacts(from: existingVCard)
        guard let existing = existingContacts.first else {
            throw ClawMailError.serverError("Failed to parse existing contact")
        }

        let newDisplayName = request.displayName ?? existing.formattedName ?? ""
        let newFirstName = request.firstName ?? existing.firstName
        let newLastName = request.lastName ?? existing.lastName
        let newOrganization = request.organization ?? existing.organization
        let newTitle = request.title ?? existing.title
        let newNotes = request.notes ?? existing.notes

        let newEmails: [(type: String, address: String)]
        if let requestEmails = request.emails {
            newEmails = requestEmails.map { ($0.type, $0.address) }
        } else {
            newEmails = existing.emails
        }

        let newPhones: [(type: String, number: String)]
        if let requestPhones = request.phones {
            newPhones = requestPhones.map { ($0.type, $0.number) }
        } else {
            newPhones = existing.phones
        }

        let updatedVCard = VCardParser.buildVCard(
            uid: id,
            formattedName: newDisplayName,
            firstName: newFirstName,
            lastName: newLastName,
            emails: newEmails,
            phones: newPhones,
            organization: newOrganization,
            title: newTitle,
            notes: newNotes
        )

        try await client.updateContact(addressBook: book.href, uid: id, vcard: updatedVCard)

        let resultEmails: [ContactEmail]
        if let requestEmails = request.emails {
            resultEmails = requestEmails
        } else {
            resultEmails = existing.emails.map { ContactEmail(type: $0.type, address: $0.address) }
        }

        let resultPhones: [ContactPhone]
        if let requestPhones = request.phones {
            resultPhones = requestPhones
        } else {
            resultPhones = existing.phones.map { ContactPhone(type: $0.type, number: $0.number) }
        }

        return Contact(
            id: id,
            addressBook: book.displayName,
            displayName: newDisplayName,
            firstName: newFirstName,
            lastName: newLastName,
            emails: resultEmails,
            phones: resultPhones,
            organization: newOrganization,
            title: newTitle,
            notes: newNotes
        )
    }

    /// Delete a contact by ID (UID).
    public func deleteContact(id: String) async throws {
        let books = try await client.listAddressBooks()

        for book in books {
            let vcardStrings = try await client.getContacts(addressBook: book.href)
            for vcs in vcardStrings {
                if let uid = VCardParser.extractUID(from: vcs), uid == id {
                    try await client.deleteContact(addressBook: book.href, uid: id)
                    return
                }
            }
        }

        throw ClawMailError.invalidParameter("Contact with ID '\(id)' not found")
    }

    // MARK: - Private Helpers

    /// Convert a parsed vCard into a Contact model.
    private func contactModel(from parsed: VCardParser.ParsedContact, addressBookName: String) -> Contact {
        let emails = parsed.emails.map { ContactEmail(type: $0.type, address: $0.address) }
        let phones = parsed.phones.map { ContactPhone(type: $0.type, number: $0.number) }

        return Contact(
            id: parsed.uid,
            addressBook: addressBookName,
            displayName: parsed.formattedName ?? "",
            firstName: parsed.firstName,
            lastName: parsed.lastName,
            emails: emails,
            phones: phones,
            organization: parsed.organization,
            title: parsed.title,
            notes: parsed.notes
        )
    }
}
