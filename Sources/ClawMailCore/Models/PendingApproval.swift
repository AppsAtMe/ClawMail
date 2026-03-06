import Foundation

public enum PendingApprovalStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
}

public enum PendingApprovalOperation: String, Codable, Sendable {
    case send
    case reply
    case forward
}

public struct PendingApproval: Codable, Equatable, Identifiable, Sendable {
    public var requestId: String
    public var accountLabel: String
    public var emails: [String]
    public var createdAt: Date
    public var status: PendingApprovalStatus
    public var operation: PendingApprovalOperation
    public var subject: String?

    public var id: String { requestId }

    public init(
        requestId: String,
        accountLabel: String,
        emails: [String],
        createdAt: Date,
        status: PendingApprovalStatus,
        operation: PendingApprovalOperation,
        subject: String? = nil
    ) {
        self.requestId = requestId
        self.accountLabel = accountLabel
        self.emails = emails
        self.createdAt = createdAt
        self.status = status
        self.operation = operation
        self.subject = subject
    }
}

struct PendingApprovalRequestEnvelope: Codable, Sendable {
    var requestId: String
    var interface: AgentInterface
    var payload: PendingApprovalRequestPayload

    init(
        requestId: String = UUID().uuidString,
        interface: AgentInterface,
        payload: PendingApprovalRequestPayload
    ) {
        self.requestId = requestId
        self.interface = interface
        self.payload = payload
    }

    var operation: PendingApprovalOperation {
        payload.operation
    }

    var accountLabel: String {
        payload.accountLabel
    }

    var subject: String? {
        payload.subject
    }
}

enum PendingApprovalRequestPayload: Sendable {
    case send(SendEmailRequest)
    case reply(ReplyEmailRequest)
    case forward(ForwardEmailRequest)

    fileprivate enum CodingKeys: String, CodingKey {
        case kind
        case send
        case reply
        case forward
    }

    fileprivate enum Kind: String, Codable {
        case send
        case reply
        case forward
    }

    var operation: PendingApprovalOperation {
        switch self {
        case .send: return .send
        case .reply: return .reply
        case .forward: return .forward
        }
    }

    var accountLabel: String {
        switch self {
        case .send(let request): return request.account
        case .reply(let request): return request.account
        case .forward(let request): return request.account
        }
    }

    var subject: String? {
        switch self {
        case .send(let request):
            return request.subject
        case .reply:
            return nil
        case .forward:
            return nil
        }
    }
}

extension PendingApprovalRequestPayload: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .send:
            self = .send(try container.decode(SendEmailRequest.self, forKey: .send))
        case .reply:
            self = .reply(try container.decode(ReplyEmailRequest.self, forKey: .reply))
        case .forward:
            self = .forward(try container.decode(ForwardEmailRequest.self, forKey: .forward))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .send(let request):
            try container.encode(Kind.send, forKey: .kind)
            try container.encode(request, forKey: .send)
        case .reply(let request):
            try container.encode(Kind.reply, forKey: .kind)
            try container.encode(request, forKey: .reply)
        case .forward(let request):
            try container.encode(Kind.forward, forKey: .kind)
            try container.encode(request, forKey: .forward)
        }
    }
}
