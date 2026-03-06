import Foundation

// MARK: - Credentials

public enum Credentials: Sendable {
    case password(String)
    case oauth2(tokenProvider: OAuthTokenProvider)
}

// MARK: - CredentialStore

public actor CredentialStore {
    private static let refreshRedirectURI = "http://127.0.0.1/clawmail/oauth-refresh"

    private let keychainManager: KeychainManager
    private let configLoader: @Sendable () throws -> AppConfig
    private let oauthSession: URLSession

    public init(
        keychainManager: KeychainManager,
        configLoader: @escaping @Sendable () throws -> AppConfig = { try AppConfig.load() },
        oauthSession: URLSession = .shared
    ) {
        self.keychainManager = keychainManager
        self.configLoader = configLoader
        self.oauthSession = oauthSession
    }

    public func credentialsFor(account: Account) async throws -> Credentials {
        switch account.authMethod {
        case .password:
            guard let password = await keychainManager.getPassword(accountId: account.id) else {
                throw ClawMailError.authFailed("No password stored for account '\(account.label)'")
            }
            return .password(password)

        case .oauth2(let provider):
            guard await keychainManager.getOAuthTokens(accountId: account.id) != nil else {
                throw ClawMailError.authFailed("No OAuth2 tokens stored for account '\(account.label)'")
            }
            let accountId = account.id
            return .oauth2(tokenProvider: OAuthTokenProvider {
                try await self.currentAccessToken(accountId: accountId, provider: provider)
            })
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

    private func currentAccessToken(accountId: UUID, provider: OAuthProvider) async throws -> String {
        let appConfig = try configLoader()
        let clientId = OAuthHelpers.oauthClientId(for: provider, appConfig: appConfig)
        guard !clientId.isEmpty else {
            throw ClawMailError.authFailed("OAuth client ID not configured for \(provider.rawValue)")
        }

        let clientSecret = await keychainManager.getOAuthClientSecret(for: provider)
        let oauthManager = OAuth2Manager(keychainManager: keychainManager, session: oauthSession)
        let oauthConfig = OAuthHelpers.oauthConfig(
            for: provider,
            appConfig: appConfig,
            clientSecret: clientSecret,
            redirectURI: Self.refreshRedirectURI
        )
        await oauthManager.setConfig(oauthConfig, for: provider)
        return try await oauthManager.getAccessToken(accountId: accountId, provider: provider)
    }
}
