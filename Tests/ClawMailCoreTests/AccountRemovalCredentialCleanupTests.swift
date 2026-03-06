import Foundation
import Testing
@testable import ClawMailCore

@Suite(.serialized)
struct AccountRemovalCredentialCleanupTests {

    @Test func removingAccountDeletesStoredPassword() async throws {
        let account = makeAccount(label: "password-account", authMethod: .password)
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.remove-account.\(UUID().uuidString)")
        let credentialStore = CredentialStore(keychainManager: keychainManager)
        defer {
            Task {
                try? await keychainManager.deleteAll(accountId: account.id)
            }
        }

        try await keychainManager.savePassword(accountId: account.id, password: "top-secret")

        let orchestrator = try AccountOrchestrator(
            config: AppConfig(accounts: [account]),
            databaseManager: try DatabaseManager(inMemory: true),
            credentialStore: credentialStore,
            configSaver: { _ in }
        )

        try await orchestrator.removeAccount(label: account.label)
        let accounts = await orchestrator.listAccounts()

        #expect(await keychainManager.getPassword(accountId: account.id) == nil)
        #expect(accounts.isEmpty)
    }

    @Test func removingAccountDeletesStoredOAuthTokens() async throws {
        let account = makeAccount(label: "oauth-account", authMethod: .oauth2(provider: .google))
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.remove-account.\(UUID().uuidString)")
        let credentialStore = CredentialStore(keychainManager: keychainManager)
        defer {
            Task {
                try? await keychainManager.deleteAll(accountId: account.id)
            }
        }

        try await keychainManager.saveOAuthTokens(
            accountId: account.id,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: .distantFuture
        )

        let orchestrator = try AccountOrchestrator(
            config: AppConfig(accounts: [account]),
            databaseManager: try DatabaseManager(inMemory: true),
            credentialStore: credentialStore,
            configSaver: { _ in }
        )

        try await orchestrator.removeAccount(label: account.label)
        let accounts = await orchestrator.listAccounts()

        #expect(await keychainManager.getOAuthTokens(accountId: account.id) == nil)
        #expect(accounts.isEmpty)
    }

    private func makeAccount(label: String, authMethod: AuthMethod) -> Account {
        Account(
            label: label,
            emailAddress: "\(label)@example.com",
            displayName: "Test User",
            authMethod: authMethod,
            imapHost: "imap.example.com",
            smtpHost: "smtp.example.com",
            isEnabled: false
        )
    }
}
