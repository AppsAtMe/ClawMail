import Foundation
@testable import ClawMailCore

/// Test constants for the GreenMail + Radicale Docker test infrastructure.
enum TestConfig {
    // GreenMail IMAP/SMTP
    static let imapHost = "127.0.0.1"
    static let imapPort = 3143
    static let imapsPort = 3993
    static let smtpHost = "127.0.0.1"
    static let smtpPort = 3025
    static let smtpsPort = 3465

    // Test users (configured in docker-compose.yml)
    static let testUser = "testuser@clawmail.test"
    static let testPass = "testpass"
    static let senderUser = "sender@clawmail.test"
    static let senderPass = "senderpass"

    // Radicale CalDAV/CardDAV
    static let caldavURL = URL(string: "http://127.0.0.1:5232")!
    static let carddavURL = URL(string: "http://127.0.0.1:5232")!

    // GreenMail API
    static let greenmailAPIURL = URL(string: "http://127.0.0.1:8080")!

    /// Check if the test infrastructure (Docker) is running.
    static func isInfrastructureAvailable() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        result.initialize(to: false)

        let url = greenmailAPIURL.appendingPathComponent("api/user")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result.pointee = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        let available = result.pointee
        result.deinitialize(count: 1)
        result.deallocate()
        return available
    }

    /// Create a test Account pointing to local GreenMail.
    static func testAccount(label: String = "test") -> Account {
        Account(
            label: label,
            emailAddress: testUser,
            displayName: "Test User",
            authMethod: .password,
            imapHost: imapHost,
            imapPort: imapPort,
            imapSecurity: .starttls,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            smtpSecurity: .starttls
        )
    }

    /// Create a sender Account pointing to local GreenMail.
    static func senderAccount(label: String = "sender") -> Account {
        Account(
            label: label,
            emailAddress: senderUser,
            displayName: "Sender User",
            authMethod: .password,
            imapHost: imapHost,
            imapPort: imapPort,
            imapSecurity: .starttls,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            smtpSecurity: .starttls
        )
    }

    /// Create an in-memory DatabaseManager for testing.
    static func inMemoryDatabase() throws -> DatabaseManager {
        try DatabaseManager(inMemory: true)
    }

    /// Create an AppConfig for testing with the given accounts.
    static func testConfig(accounts: [Account] = []) -> AppConfig {
        AppConfig(
            accounts: accounts,
            restApiPort: 24602, // Different port to avoid conflicts
            guardrails: GuardrailConfig(),
            syncIntervalMinutes: 1,
            initialSyncDays: 7
        )
    }
}
