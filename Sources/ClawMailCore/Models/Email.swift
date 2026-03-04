import Foundation

// MARK: - EmailAddress

public struct EmailAddress: Codable, Sendable, Equatable, Hashable {
    public var name: String?
    public var email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }

    public var displayString: String {
        if let name = name, !name.isEmpty {
            return "\(name) <\(email)>"
        }
        return email
    }

    public var domain: String {
        email.components(separatedBy: "@").last ?? ""
    }
}

// MARK: - EmailFlag

public enum EmailFlag: String, Codable, Sendable, Equatable, Hashable {
    case seen
    case flagged
    case answered
    case draft
}

// MARK: - EmailSummary

public struct EmailSummary: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var account: String
    public var folder: String
    public var from: EmailAddress
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var subject: String?
    public var date: Date
    public var flags: Set<EmailFlag>
    public var size: Int?
    public var hasAttachments: Bool
    public var uid: UInt32?
    public var messageId: String?
    public var inReplyTo: String?
    public var references: String?
    public var preview: String?

    public init(
        id: String,
        account: String,
        folder: String,
        from: EmailAddress,
        to: [EmailAddress],
        cc: [EmailAddress] = [],
        subject: String? = nil,
        date: Date,
        flags: Set<EmailFlag> = [],
        size: Int? = nil,
        hasAttachments: Bool = false,
        uid: UInt32? = nil,
        messageId: String? = nil,
        inReplyTo: String? = nil,
        references: String? = nil,
        preview: String? = nil
    ) {
        self.id = id
        self.account = account
        self.folder = folder
        self.from = from
        self.to = to
        self.cc = cc
        self.subject = subject
        self.date = date
        self.flags = flags
        self.size = size
        self.hasAttachments = hasAttachments
        self.uid = uid
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
        self.preview = preview
    }
}

// MARK: - EmailMessage

public struct EmailMessage: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var account: String
    public var folder: String
    public var from: EmailAddress
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String?
    public var date: Date
    public var flags: Set<EmailFlag>
    public var bodyPlain: String?
    public var bodyPlainRaw: String?
    public var bodyHtml: String?
    public var attachments: [EmailAttachment]
    public var headers: [String: String]

    public init(
        id: String,
        account: String,
        folder: String,
        from: EmailAddress,
        to: [EmailAddress],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String? = nil,
        date: Date,
        flags: Set<EmailFlag> = [],
        bodyPlain: String? = nil,
        bodyPlainRaw: String? = nil,
        bodyHtml: String? = nil,
        attachments: [EmailAttachment] = [],
        headers: [String: String] = [:]
    ) {
        self.id = id
        self.account = account
        self.folder = folder
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.date = date
        self.flags = flags
        self.bodyPlain = bodyPlain
        self.bodyPlainRaw = bodyPlainRaw
        self.bodyHtml = bodyHtml
        self.attachments = attachments
        self.headers = headers
    }
}

// MARK: - EmailAttachment

public struct EmailAttachment: Codable, Sendable, Equatable {
    public var filename: String
    public var mimeType: String
    public var size: Int
    public var section: String?

    public init(filename: String, mimeType: String, size: Int, section: String? = nil) {
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.section = section
    }
}

// MARK: - SendEmailRequest

public struct SendEmailRequest: Codable, Sendable {
    public var account: String
    public var to: [EmailAddress]
    public var cc: [EmailAddress]?
    public var bcc: [EmailAddress]?
    public var subject: String
    public var body: String
    public var bodyHtml: String?
    public var attachments: [String]?
    public var inReplyTo: String?

    public init(
        account: String,
        to: [EmailAddress],
        cc: [EmailAddress]? = nil,
        bcc: [EmailAddress]? = nil,
        subject: String,
        body: String,
        bodyHtml: String? = nil,
        attachments: [String]? = nil,
        inReplyTo: String? = nil
    ) {
        self.account = account
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.bodyHtml = bodyHtml
        self.attachments = attachments
        self.inReplyTo = inReplyTo
    }
}

// MARK: - ReplyEmailRequest

public struct ReplyEmailRequest: Codable, Sendable {
    public var account: String
    public var originalMessageId: String
    public var body: String
    public var bodyHtml: String?
    public var attachments: [String]?
    public var replyAll: Bool

    public init(
        account: String,
        originalMessageId: String,
        body: String,
        bodyHtml: String? = nil,
        attachments: [String]? = nil,
        replyAll: Bool = false
    ) {
        self.account = account
        self.originalMessageId = originalMessageId
        self.body = body
        self.bodyHtml = bodyHtml
        self.attachments = attachments
        self.replyAll = replyAll
    }
}

// MARK: - ForwardEmailRequest

public struct ForwardEmailRequest: Codable, Sendable {
    public var account: String
    public var originalMessageId: String
    public var to: [EmailAddress]
    public var body: String?
    public var attachments: [String]?

    public init(
        account: String,
        originalMessageId: String,
        to: [EmailAddress],
        body: String? = nil,
        attachments: [String]? = nil
    ) {
        self.account = account
        self.originalMessageId = originalMessageId
        self.to = to
        self.body = body
        self.attachments = attachments
    }
}

// MARK: - FolderInfo

public struct FolderInfo: Codable, Sendable, Equatable {
    public var name: String
    public var path: String
    public var unreadCount: Int
    public var totalCount: Int
    public var children: [FolderInfo]

    public init(name: String, path: String, unreadCount: Int = 0, totalCount: Int = 0, children: [FolderInfo] = []) {
        self.name = name
        self.path = path
        self.unreadCount = unreadCount
        self.totalCount = totalCount
        self.children = children
    }
}

// MARK: - SortOrder

public enum SortOrder: String, Codable, Sendable {
    case dateAscending = "date_asc"
    case dateDescending = "date_desc"
}
