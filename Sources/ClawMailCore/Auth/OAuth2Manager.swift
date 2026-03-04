import Foundation

// MARK: - OAuthConfig

public struct OAuthConfig: Sendable {
    public let clientId: String
    public let clientSecret: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let scopes: [String]
    public let redirectURI: String

    public static func google(clientId: String, clientSecret: String? = nil) -> OAuthConfig {
        OAuthConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            scopes: [
                "https://mail.google.com/",
                "https://www.googleapis.com/auth/calendar",
                "https://www.googleapis.com/auth/contacts",
            ],
            redirectURI: "http://127.0.0.1:0/oauth/callback"
        )
    }

    public static func microsoft(clientId: String, clientSecret: String? = nil) -> OAuthConfig {
        OAuthConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            scopes: [
                "offline_access",
                "IMAP.AccessAsUser.All",
                "SMTP.Send",
                "Calendars.ReadWrite",
                "Contacts.ReadWrite",
                "Tasks.ReadWrite",
            ],
            redirectURI: "http://127.0.0.1:0/oauth/callback"
        )
    }
}

// MARK: - OAuth2Manager

public actor OAuth2Manager {
    private static let formSafeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private let keychainManager: KeychainManager
    private var configs: [OAuthProvider: OAuthConfig] = [:]

    public init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
    }

    public func setConfig(_ config: OAuthConfig, for provider: OAuthProvider) {
        configs[provider] = config
    }

    // MARK: - Authorization Flow

    public func buildAuthorizationURL(provider: OAuthProvider, state: String) throws -> URL {
        guard let config = configs[provider] else {
            throw ClawMailError.serverError("OAuth2 not configured for \(provider.rawValue)")
        }

        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let url = components.url else {
            throw ClawMailError.serverError("Failed to build authorization URL")
        }
        return url
    }

    // MARK: - Token Exchange

    public func exchangeCodeForTokens(
        code: String,
        provider: OAuthProvider,
        redirectURI: String
    ) async throws -> OAuthTokens {
        guard let config = configs[provider] else {
            throw ClawMailError.serverError("OAuth2 not configured for \(provider.rawValue)")
        }

        var body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": config.clientId,
        ]
        if let secret = config.clientSecret {
            body["client_secret"] = secret
        }

        let tokens = try await postTokenRequest(url: config.tokenEndpoint, body: body)
        return tokens
    }

    // MARK: - Token Management

    public func getAccessToken(accountId: UUID, provider: OAuthProvider) async throws -> String {
        guard let tokens = await keychainManager.getOAuthTokens(accountId: accountId) else {
            throw ClawMailError.authFailed("No OAuth2 tokens found")
        }

        if !tokens.isExpired {
            return tokens.accessToken
        }

        // Refresh the token
        return try await refreshAccessToken(accountId: accountId, refreshToken: tokens.refreshToken, provider: provider)
    }

    public func refreshAccessToken(accountId: UUID, refreshToken: String, provider: OAuthProvider) async throws -> String {
        guard let config = configs[provider] else {
            throw ClawMailError.serverError("OAuth2 not configured for \(provider.rawValue)")
        }

        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId,
        ]
        if let secret = config.clientSecret {
            body["client_secret"] = secret
        }

        let tokens = try await postTokenRequest(url: config.tokenEndpoint, body: body)

        // Save new tokens (keep the old refresh token if a new one wasn't provided)
        try await keychainManager.saveOAuthTokens(
            accountId: accountId,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )

        return tokens.accessToken
    }

    public func saveTokens(accountId: UUID, tokens: OAuthTokens) async throws {
        try await keychainManager.saveOAuthTokens(
            accountId: accountId,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt
        )
    }

    public func revokeTokens(accountId: UUID) async throws {
        try await keychainManager.deleteOAuthTokens(accountId: accountId)
    }

    // MARK: - XOAUTH2

    public static func buildXOAuth2String(email: String, accessToken: String) -> String {
        let authString = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        return Data(authString.utf8).base64EncodedString()
    }

    // MARK: - HTTP

    private func postTokenRequest(url: URL, body: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = body.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: Self.formSafeChars) ?? value)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawMailError.connectionError("Invalid token response")
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClawMailError.authFailed("Token request failed (\(httpResponse.statusCode)): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        guard let accessToken = json["access_token"] as? String else {
            throw ClawMailError.authFailed("No access_token in response")
        }

        let refreshToken = json["refresh_token"] as? String ?? body["refresh_token"] ?? ""
        let expiresIn = json["expires_in"] as? Int ?? 3600
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn - 60)) // 60s buffer

        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}
