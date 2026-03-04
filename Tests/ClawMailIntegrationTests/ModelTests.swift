import Testing
import Foundation
@testable import ClawMailCore

/// Tests for core model types: serialization, config persistence, metadata operations.
@Suite
struct ModelTests {

    // MARK: - AppConfig Persistence

    @Test func configSaveAndLoad() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawmail-test-\(UUID().uuidString)")
            .appendingPathComponent("config.json")

        var config = AppConfig()
        config.restApiPort = 9999
        config.syncIntervalMinutes = 5
        config.guardrails.firstTimeRecipientApproval = true
        config.guardrails.domainBlocklist = ["spam.com", "phish.com"]
        config.webhookURL = "https://example.com/webhook"

        try config.save(to: tempURL)
        let loaded = try AppConfig.load(from: tempURL)

        #expect(loaded.restApiPort == 9999)
        #expect(loaded.syncIntervalMinutes == 5)
        #expect(loaded.guardrails.firstTimeRecipientApproval == true)
        #expect(loaded.guardrails.domainBlocklist == ["spam.com", "phish.com"])
        #expect(loaded.webhookURL == "https://example.com/webhook")

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    // MARK: - Account JSON Round-trip

    @Test func accountCodableRoundTrip() throws {
        let account = Account(
            label: "work",
            emailAddress: "user@company.com",
            displayName: "Work User",
            authMethod: .oauth2(provider: .google),
            imapHost: "imap.gmail.com",
            imapPort: 993,
            imapSecurity: .ssl,
            smtpHost: "smtp.gmail.com",
            smtpPort: 465,
            smtpSecurity: .ssl,
            caldavURL: URL(string: "https://caldav.google.com"),
            carddavURL: URL(string: "https://carddav.google.com")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(account)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Account.self, from: data)

        #expect(decoded.label == "work")
        #expect(decoded.emailAddress == "user@company.com")
        #expect(decoded.authMethod == .oauth2(provider: .google))
        #expect(decoded.imapHost == "imap.gmail.com")
        #expect(decoded.smtpPort == 465)
        #expect(decoded.caldavURL?.absoluteString == "https://caldav.google.com")
    }

    // MARK: - ClawMailError Codable

    @Test func errorCodableRoundTrip() throws {
        let errors: [ClawMailError] = [
            .accountNotFound("test"),
            .rateLimitExceeded(retryAfterSeconds: 60),
            .domainBlocked("spam.com"),
            .recipientPendingApproval(emails: ["new@example.com"]),
            .agentAlreadyConnected,
            .calendarNotAvailable,
        ]

        for error in errors {
            let data = try JSONEncoder().encode(error)
            let decoded = try JSONDecoder().decode(ClawMailError.self, from: data)
            #expect(decoded.code == error.code)
        }
    }

    // MARK: - ErrorResponse Format

    @Test func errorResponseFormat() {
        let error = ClawMailError.rateLimitExceeded(retryAfterSeconds: 30)
        let response = ErrorResponse(from: error)

        #expect(response.error.code == "RATE_LIMIT_EXCEEDED")
        #expect(response.error.message.contains("30"))

        let json = response.toJSONString()
        #expect(json.contains("RATE_LIMIT_EXCEEDED"))
    }

    // MARK: - Metadata Index CRUD

    @Test func metadataIndexUpsertAndQuery() throws {
        let db = try TestConfig.inMemoryDatabase()
        let index = MetadataIndex(db: db)

        let summary = EmailSummary(
            id: "msg-001",
            account: "test",
            folder: "INBOX",
            from: EmailAddress(name: "Sender", email: "sender@example.com"),
            to: [EmailAddress(name: "Recipient", email: "recipient@example.com")],
            cc: [],
            subject: "Test Subject",
            date: Date(),
            flags: [.seen],
            size: 1024,
            hasAttachments: false
        )

        try index.upsertMessage(summary, bodyText: "Hello world test body")

        let results = try index.search(account: "test", query: "test body")
        #expect(!results.isEmpty)
    }

    // MARK: - Approved Recipients

    @Test func approvedRecipientsLifecycle() throws {
        let db = try TestConfig.inMemoryDatabase()
        let index = MetadataIndex(db: db)

        // Initially empty
        let empty = try index.listApprovedRecipients()
        #expect(empty.isEmpty)

        // Approve a recipient
        try index.approveRecipient(email: "approved@example.com", account: "test")

        let approved = try index.listApprovedRecipients()
        #expect(approved.count == 1)
        #expect(approved.first?.email == "approved@example.com")

        // Remove
        try index.removeApprovedRecipient(email: "approved@example.com")
        let removed = try index.listApprovedRecipients()
        #expect(removed.isEmpty)
    }

    // MARK: - AnyCodableValue

    @Test func anyCodableValueRoundTrip() throws {
        let values: [String: AnyCodableValue] = [
            "string": .string("hello"),
            "int": .int(42),
            "bool": .bool(true),
            "double": .double(3.14),
            "null": .null,
            "array": .array([.string("a"), .int(1)]),
            "dict": .dictionary(["nested": .string("value")]),
        ]

        let data = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: data)

        #expect(decoded["string"] == .string("hello"))
        #expect(decoded["int"] == .int(42))
        #expect(decoded["bool"] == .bool(true))
        #expect(decoded["null"] == .null)
    }
}
