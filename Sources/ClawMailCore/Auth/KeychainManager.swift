import Foundation
import KeychainAccess

public actor KeychainManager {
    private let keychain: Keychain
    private static let serviceName = "com.clawmail"
    private static let apiKeyAccount = "clawmail-api-key"

    public init(serviceName: String = "com.clawmail") {
        // Use thisDeviceOnly to prevent OAuth tokens and credentials from syncing via iCloud Keychain
        self.keychain = Keychain(service: serviceName)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
    }

    // MARK: - Password Storage

    public func savePassword(accountId: UUID, password: String) throws {
        try keychain.set(password, key: passwordKey(accountId))
    }

    public func getPassword(accountId: UUID) -> String? {
        try? keychain.get(passwordKey(accountId))
    }

    public func deletePassword(accountId: UUID) throws {
        try keychain.remove(passwordKey(accountId))
    }

    // MARK: - OAuth2 Token Storage

    public func saveOAuthTokens(accountId: UUID, accessToken: String, refreshToken: String, expiresAt: Date) throws {
        let tokens = OAuthTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        try saveOAuthTokens(accountId: accountId, tokens: tokens)
    }

    public func saveOAuthTokens(accountId: UUID, tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ClawMailError.serverError("Failed to encode OAuth tokens as UTF-8")
        }
        try keychain.set(string, key: oauthKey(accountId))
    }

    public func getOAuthTokens(accountId: UUID) -> OAuthTokens? {
        guard let string = try? keychain.get(oauthKey(accountId)),
              let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func deleteOAuthTokens(accountId: UUID) throws {
        try keychain.remove(oauthKey(accountId))
    }

    // MARK: - API Key

    public func saveAPIKey(_ key: String) throws {
        try keychain.set(key, key: Self.apiKeyAccount)
    }

    public func getAPIKey() -> String? {
        try? keychain.get(Self.apiKeyAccount)
    }

    public func generateAPIKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ClawMailError.serverError("Failed to generate random bytes for API key")
        }
        let key = bytes.map { String(format: "%02x", $0) }.joined()
        try saveAPIKey(key)
        return key
    }

    // MARK: - OAuth Client Secrets

    private static let googleSecretAccount = "clawmail-oauth-google-secret"
    private static let microsoftSecretAccount = "clawmail-oauth-microsoft-secret"

    public func saveOAuthClientSecret(_ secret: String, for provider: OAuthProvider) throws {
        let key = provider == .google ? Self.googleSecretAccount : Self.microsoftSecretAccount
        try keychain.set(secret, key: key)
    }

    public func getOAuthClientSecret(for provider: OAuthProvider) -> String? {
        let key = provider == .google ? Self.googleSecretAccount : Self.microsoftSecretAccount
        return try? keychain.get(key)
    }

    public func deleteOAuthClientSecret(for provider: OAuthProvider) throws {
        let key = provider == .google ? Self.googleSecretAccount : Self.microsoftSecretAccount
        try keychain.remove(key)
    }

    // MARK: - Cleanup

    public func deleteAll(accountId: UUID) throws {
        try keychain.remove(passwordKey(accountId))
        try keychain.remove(oauthKey(accountId))
    }

    // MARK: - Key Helpers

    private func passwordKey(_ accountId: UUID) -> String {
        "password-\(accountId.uuidString)"
    }

    private func oauthKey(_ accountId: UUID) -> String {
        "oauth-\(accountId.uuidString)"
    }
}
