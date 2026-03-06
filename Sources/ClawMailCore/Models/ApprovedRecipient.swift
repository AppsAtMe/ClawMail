import Foundation

public struct ApprovedRecipient: Codable, Equatable, Identifiable, Sendable {
    public var email: String
    public var accountLabel: String
    public var approvedAt: Date

    public var id: String {
        "\(accountLabel):\(email)"
    }

    public init(email: String, accountLabel: String, approvedAt: Date) {
        self.email = email
        self.accountLabel = accountLabel
        self.approvedAt = approvedAt
    }
}
