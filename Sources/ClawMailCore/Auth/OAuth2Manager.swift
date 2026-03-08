import Foundation
import CryptoKit
import Security

// MARK: - OAuthConfig

public struct OAuthConfig: Sendable {
    public let clientId: String
    public let clientSecret: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let scopes: [String]
    public let redirectURI: String

    public init(
        clientId: String,
        clientSecret: String?,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        scopes: [String],
        redirectURI: String
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.scopes = scopes
        self.redirectURI = redirectURI
    }

}

// MARK: - OAuth2Manager

public actor OAuth2Manager {
    private static let formSafeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    public struct PKCEChallenge: Sendable {
        public let verifier: String
        public let challenge: String
    }

    private let keychainManager: KeychainManager
    private let session: URLSession
    private var configs: [OAuthProvider: OAuthConfig] = [:]

    public init(keychainManager: KeychainManager, session: URLSession = .shared) {
        self.keychainManager = keychainManager
        self.session = session
    }

    public func setConfig(_ config: OAuthConfig, for provider: OAuthProvider) {
        configs[provider] = config
    }

    public static func generatePKCEChallenge() -> PKCEChallenge {
        let verifier = generateCodeVerifier()
        return PKCEChallenge(verifier: verifier, challenge: codeChallenge(for: verifier))
    }

    // MARK: - Authorization Flow

    public func buildAuthorizationURL(
        provider: OAuthProvider,
        state: String,
        codeChallenge: String? = nil,
        loginHint: String? = nil
    ) throws -> URL {
        guard let config = configs[provider] else {
            throw ClawMailError.serverError("OAuth2 not configured for \(provider.rawValue)")
        }

        var queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let codeChallenge {
            queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        if let loginHint = normalizedLoginHint(loginHint), provider == .google {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }

        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ClawMailError.serverError("Failed to build authorization URL")
        }
        return url
    }

    // MARK: - Token Exchange

    public func exchangeCodeForTokens(
        code: String,
        provider: OAuthProvider,
        redirectURI: String,
        codeVerifier: String? = nil
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
        if let codeVerifier {
            body["code_verifier"] = codeVerifier
        }
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
        let existingTokens = await keychainManager.getOAuthTokens(accountId: accountId)

        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId,
        ]
        if let secret = config.clientSecret {
            body["client_secret"] = secret
        }

        let tokens = try await postTokenRequest(url: config.tokenEndpoint, body: body)
        var mergedTokens = tokens
        if mergedTokens.grantedScopes == nil {
            mergedTokens.grantedScopes = existingTokens?.grantedScopes
        }
        if mergedTokens.identity == nil {
            mergedTokens.identity = existingTokens?.identity
        }

        // Save new tokens (keep the old refresh token if a new one wasn't provided)
        try await keychainManager.saveOAuthTokens(accountId: accountId, tokens: mergedTokens)

        return mergedTokens.accessToken
    }

    public func saveTokens(accountId: UUID, tokens: OAuthTokens) async throws {
        try await keychainManager.saveOAuthTokens(accountId: accountId, tokens: tokens)
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

        let (data, response) = try await session.data(for: request)

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
        let grantedScopes = parseGrantedScopes(from: json["scope"])
        let identity = parseIdentity(from: json["id_token"], expectedClientId: body["client_id"] ?? "")
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn - 60)) // 60s buffer

        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            grantedScopes: grantedScopes,
            identity: identity
        )
    }

    private func parseGrantedScopes(from rawValue: Any?) -> [String]? {
        guard let scopeString = rawValue as? String else { return nil }
        let scopes = scopeString
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        return scopes.isEmpty ? nil : scopes
    }

    private func parseIdentity(from rawValue: Any?, expectedClientId: String) -> OAuthIdentity? {
        guard let idToken = rawValue as? String,
              !expectedClientId.isEmpty,
              let claims = decodeJWTClaims(idToken),
              claims.hasTrustedGoogleIssuer,
              claims.audienceMatches(expectedClientId),
              let subject = claims.subject,
              !subject.isEmpty else {
            return nil
        }

        return OAuthIdentity(
            subject: subject,
            email: claims.email,
            emailVerified: claims.emailVerified
        )
    }

    private func decodeJWTClaims(_ token: String) -> GoogleIDTokenClaims? {
        let segments = token.split(separator: ".")
        guard segments.count == 3,
              let payload = decodeBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }
        return GoogleIDTokenClaims(payload: object)
    }

    private func decodeBase64URL(_ rawValue: String) -> Data? {
        var base64 = rawValue
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - (base64.count % 4)) % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }

    private func normalizedLoginHint(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct GoogleIDTokenClaims {
    let issuer: String?
    let audience: Any?
    let subject: String?
    let email: String?
    let emailVerified: Bool?

    init(payload: [String: Any]) {
        issuer = payload["iss"] as? String
        audience = payload["aud"]
        subject = payload["sub"] as? String
        email = payload["email"] as? String
        emailVerified = payload["email_verified"] as? Bool
    }

    var hasTrustedGoogleIssuer: Bool {
        issuer == "https://accounts.google.com" || issuer == "accounts.google.com"
    }

    func audienceMatches(_ clientId: String) -> Bool {
        if let audience = audience as? String {
            return audience == clientId
        }
        if let audience = audience as? [String] {
            return audience.contains(clientId)
        }
        return false
    }
}
