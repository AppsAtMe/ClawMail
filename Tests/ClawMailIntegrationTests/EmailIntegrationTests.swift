import Testing
import Foundation
@testable import ClawMailCore

/// Integration tests for email operations via AccountOrchestrator.
/// Requires Docker test infrastructure: `docker compose up -d`
@Suite(.serialized)
struct EmailIntegrationTests {

    // MARK: - IMAP Connection Test

    @Test func imapConnectAndList() async throws {
        try skipIfNoInfra()

        let account = TestConfig.testAccount()
        let credential = IMAPCredential.password(
            username: TestConfig.testLogin,
            password: TestConfig.testPass
        )
        let client = IMAPClient(
            host: account.imapHost,
            port: account.imapPort,
            security: account.imapSecurity,
            credential: credential,
            verifyCertificates: false  // GreenMail uses self-signed certs
        )

        try await client.connect()
        try await client.authenticate()

        let folders = try await client.listFolders()
        #expect(!folders.isEmpty, "Should have at least INBOX")

        await client.disconnect()
    }

    // MARK: - SMTP Send Test

    @Test func smtpSendEmail() async throws {
        try skipIfNoInfra()

        let creds = Credentials.password(TestConfig.senderPass)
        let client = SMTPClient(
            host: TestConfig.smtpHost,
            port: TestConfig.smtpsPort,
            security: .ssl,
            credentials: creds,
            senderEmail: TestConfig.senderLogin,  // GreenMail auth uses login part only
            verifyCertificates: false  // GreenMail uses self-signed certs
        )

        try await client.connect()

        let email = OutgoingEmail(
            from: EmailAddress(name: "Sender", email: TestConfig.senderUser),
            to: [EmailAddress(name: "Test User", email: TestConfig.testUser)],
            subject: "Integration Test \(UUID().uuidString.prefix(8))",
            bodyPlain: "This is a test email from the integration test suite."
        )

        let messageId = try await client.send(message: email)
        #expect(!messageId.isEmpty, "Should return a message ID")

        try await client.disconnect()
    }

    // MARK: - Full Email Lifecycle (Orchestrator)

    @Test func orchestratorEmailLifecycle() async throws {
        try skipIfNoInfra()

        let db = try TestConfig.inMemoryDatabase()
        let account = TestConfig.testAccount()
        let config = TestConfig.testConfig(accounts: [account])
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        // Note: In a full test, we'd save password to keychain first.
        // For now, we test the orchestrator structure without live connection.
        let accounts = await orchestrator.listAccounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.label == "test")
        #expect(accounts.first?.emailAddress == TestConfig.testUser)

        await orchestrator.stop()
    }

    // MARK: - Audit Logging

    @Test func auditLogRecordsOperations() async throws {
        let db = try TestConfig.inMemoryDatabase()

        let auditLog = AuditLog(db: db)

        // Log a test entry
        try auditLog.log(entry: AuditEntry(
            interface: .cli,
            operation: "email.send",
            account: "test",
            parameters: [
                "to": .string("recipient@example.com"),
                "subject": .string("Test Subject"),
            ],
            result: .success,
            details: ["messageId": .string("msg-123")]
        ))

        // Query it back
        let entries = try auditLog.list(limit: 10)
        #expect(entries.count == 1)
        #expect(entries.first?.operation == "email.send")
        #expect(entries.first?.result == .success)
        #expect(entries.first?.account == "test")
    }

    // MARK: - Guardrail Engine

    @Test func guardrailBlocksDomain() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let metadataIndex = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        let guardrailConfig = GuardrailConfig(
            domainBlocklist: ["blocked.com"]
        )
        let engine = GuardrailEngine(
            config: { guardrailConfig },
            auditLog: auditLog,
            metadataIndex: metadataIndex
        )

        let result = try await engine.checkSend(
            account: "test",
            recipients: [EmailAddress(name: nil, email: "user@blocked.com")]
        )

        switch result {
        case .blocked:
            // Expected
            break
        case .allowed, .pendingApproval:
            #expect(Bool(false), "Should have blocked the send to blocked.com")
        }
    }

    @Test func guardrailAllowsValidDomain() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let metadataIndex = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        let guardrailConfig = GuardrailConfig(
            domainAllowlist: ["allowed.com"]
        )
        let engine = GuardrailEngine(
            config: { guardrailConfig },
            auditLog: auditLog,
            metadataIndex: metadataIndex
        )

        let result = try await engine.checkSend(
            account: "test",
            recipients: [EmailAddress(name: nil, email: "user@allowed.com")]
        )

        switch result {
        case .allowed:
            break // Expected
        case .blocked, .pendingApproval:
            #expect(Bool(false), "Should have allowed the send to allowed.com")
        }
    }

    @Test func guardrailBlocksUnallowedDomain() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let metadataIndex = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        let guardrailConfig = GuardrailConfig(
            domainAllowlist: ["allowed.com"]
        )
        let engine = GuardrailEngine(
            config: { guardrailConfig },
            auditLog: auditLog,
            metadataIndex: metadataIndex
        )

        let result = try await engine.checkSend(
            account: "test",
            recipients: [EmailAddress(name: nil, email: "user@notallowed.com")]
        )

        switch result {
        case .blocked:
            break // Expected
        case .allowed, .pendingApproval:
            #expect(Bool(false), "Should have blocked the send to notallowed.com")
        }
    }

    // MARK: - Helpers

    private func skipIfNoInfra() throws {
        if !TestConfig.isInfrastructureAvailable() {
            throw TestSkipped("Docker test infrastructure not available (run 'docker compose up -d')")
        }
    }
}
