import Foundation
import Testing
@testable import ClawMailCore

@Suite(.serialized)
struct AccountUpdateTests {

    @Test func updatingDisabledAccountPersistsNewServiceConfiguration() async throws {
        let original = makeAccount(label: "Mac.com")
        let updatedCalDAV = try #require(URL(string: "https://caldav.icloud.com"))
        let updatedCardDAV = try #require(URL(string: "https://contacts.icloud.com"))
        let saver = ConfigCapture()

        let orchestrator = try AccountOrchestrator(
            config: AppConfig(accounts: [original]),
            databaseManager: try DatabaseManager(inMemory: true),
            configSaver: { config in
                saver.record(config)
            }
        )

        let updated = Account(
            id: original.id,
            label: original.label,
            emailAddress: original.emailAddress,
            displayName: "Updated Display Name",
            authMethod: original.authMethod,
            imapHost: original.imapHost,
            imapPort: original.imapPort,
            imapSecurity: original.imapSecurity,
            smtpHost: original.smtpHost,
            smtpPort: original.smtpPort,
            smtpSecurity: original.smtpSecurity,
            caldavURL: updatedCalDAV,
            carddavURL: updatedCardDAV,
            isEnabled: false
        )

        try await orchestrator.updateAccount(label: original.label, with: updated)

        let saved = await orchestrator.listAccounts()
        #expect(saved == [updated])
        #expect(saver.lastConfig?.accounts == [updated])
    }

    @Test func updatingAccountRejectsRenameRequests() async throws {
        let original = makeAccount(label: "Mac.com")
        let orchestrator = try AccountOrchestrator(
            config: AppConfig(accounts: [original]),
            databaseManager: try DatabaseManager(inMemory: true),
            configSaver: { _ in }
        )

        let renamed = Account(
            id: original.id,
            label: "Personal",
            emailAddress: original.emailAddress,
            displayName: original.displayName,
            authMethod: original.authMethod,
            imapHost: original.imapHost,
            imapPort: original.imapPort,
            imapSecurity: original.imapSecurity,
            smtpHost: original.smtpHost,
            smtpPort: original.smtpPort,
            smtpSecurity: original.smtpSecurity,
            isEnabled: false
        )

        await #expect(throws: ClawMailError.self) {
            try await orchestrator.updateAccount(label: original.label, with: renamed)
        }
    }

    private func makeAccount(label: String) -> Account {
        Account(
            label: label,
            emailAddress: "test@example.com",
            displayName: "Test User",
            authMethod: .password,
            imapHost: "imap.mail.me.com",
            smtpHost: "smtp.mail.me.com",
            isEnabled: false
        )
    }
}

private final class ConfigCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var configs: [AppConfig] = []

    var lastConfig: AppConfig? {
        lock.lock()
        defer { lock.unlock() }
        return configs.last
    }

    func record(_ config: AppConfig) {
        lock.lock()
        defer { lock.unlock() }
        configs.append(config)
    }
}
