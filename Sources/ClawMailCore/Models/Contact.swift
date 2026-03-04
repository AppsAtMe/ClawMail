import Foundation

// MARK: - AddressBook

public struct AddressBook: Codable, Sendable, Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

// MARK: - Contact

public struct Contact: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var addressBook: String
    public var displayName: String
    public var firstName: String?
    public var lastName: String?
    public var emails: [ContactEmail]
    public var phones: [ContactPhone]
    public var organization: String?
    public var title: String?
    public var notes: String?

    public init(
        id: String,
        addressBook: String,
        displayName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        emails: [ContactEmail] = [],
        phones: [ContactPhone] = [],
        organization: String? = nil,
        title: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.addressBook = addressBook
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.emails = emails
        self.phones = phones
        self.organization = organization
        self.title = title
        self.notes = notes
    }
}

// MARK: - ContactEmail

public struct ContactEmail: Codable, Sendable, Equatable {
    public var type: String
    public var address: String

    public init(type: String, address: String) {
        self.type = type
        self.address = address
    }
}

// MARK: - ContactPhone

public struct ContactPhone: Codable, Sendable, Equatable {
    public var type: String
    public var number: String

    public init(type: String, number: String) {
        self.type = type
        self.number = number
    }
}

// MARK: - CreateContactRequest

public struct CreateContactRequest: Codable, Sendable {
    public var account: String
    public var addressBook: String
    public var displayName: String
    public var firstName: String?
    public var lastName: String?
    public var emails: [ContactEmail]?
    public var phones: [ContactPhone]?
    public var organization: String?
    public var title: String?
    public var notes: String?

    public init(
        account: String,
        addressBook: String,
        displayName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        emails: [ContactEmail]? = nil,
        phones: [ContactPhone]? = nil,
        organization: String? = nil,
        title: String? = nil,
        notes: String? = nil
    ) {
        self.account = account
        self.addressBook = addressBook
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.emails = emails
        self.phones = phones
        self.organization = organization
        self.title = title
        self.notes = notes
    }
}

// MARK: - UpdateContactRequest

public struct UpdateContactRequest: Codable, Sendable {
    public var account: String
    public var displayName: String?
    public var firstName: String?
    public var lastName: String?
    public var emails: [ContactEmail]?
    public var phones: [ContactPhone]?
    public var organization: String?
    public var title: String?
    public var notes: String?

    public init(
        account: String,
        displayName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        emails: [ContactEmail]? = nil,
        phones: [ContactPhone]? = nil,
        organization: String? = nil,
        title: String? = nil,
        notes: String? = nil
    ) {
        self.account = account
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.emails = emails
        self.phones = phones
        self.organization = organization
        self.title = title
        self.notes = notes
    }
}
