import Foundation

// MARK: - Credentials

public enum Credentials: Sendable {
    case password(String)
    case oauth2(accessToken: String, refreshToken: String, expiresAt: Date)
}

// MARK: - CredentialStore

public actor CredentialStore {
    private let keychainManager: KeychainManager

    public init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
    }

    public func credentialsFor(account: Account) async throws -> Credentials {
        switch account.authMethod {
        case .password:
            guard let password = await keychainManager.getPassword(accountId: account.id) else {
                throw ClawMailError.authFailed("No password stored for account '\(account.label)'")
            }
            return .password(password)

        case .oauth2:
            guard let tokens = await keychainManager.getOAuthTokens(accountId: account.id) else {
                throw ClawMailError.authFailed("No OAuth2 tokens stored for account '\(account.label)'")
            }
            return .oauth2(
                accessToken: tokens.accessToken,
                refreshToken: tokens.refreshToken,
                expiresAt: tokens.expiresAt
            )
        }
    }

    public func savePassword(accountId: UUID, password: String) async throws {
        try await keychainManager.savePassword(accountId: accountId, password: password)
    }

    public func saveOAuthTokens(accountId: UUID, accessToken: String, refreshToken: String, expiresAt: Date) async throws {
        try await keychainManager.saveOAuthTokens(
            accountId: accountId,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    public func deleteCredentials(accountId: UUID) async throws {
        try await keychainManager.deleteAll(accountId: accountId)
    }

    public func getAPIKey() async -> String? {
        await keychainManager.getAPIKey()
    }

    public func generateAPIKey() async throws -> String {
        try await keychainManager.generateAPIKey()
    }
}
