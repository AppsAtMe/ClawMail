import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ClawMailCore

@Suite(.serialized)
struct OAuthRefreshTests {

    @Test func credentialStoreRefreshesExpiredTokensOnDemand() async throws {
        let session = makeSession()
        let accountId = UUID()
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-refresh.\(UUID().uuidString)")
        defer {
            Task {
                try? await keychainManager.deleteAll(accountId: accountId)
                try? await keychainManager.deleteOAuthClientSecret(for: .google)
            }
        }

        try await keychainManager.saveOAuthTokens(
            accountId: accountId,
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiresAt: .distantPast
        )
        try await keychainManager.saveOAuthClientSecret("top-secret", for: .google)

        MockOAuthURLProtocol.enqueue { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url == URL(string: "https://oauth2.googleapis.com/token"))

            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=refresh_token"))
            #expect(body.contains("refresh_token=refresh-token"))
            #expect(body.contains("client_id=test-client"))
            #expect(body.contains("client_secret=top-secret"))

            return self.response(
                url: request.url!,
                status: 200,
                body: """
                {"access_token":"fresh-token","expires_in":3600}
                """
            )
        }

        let store = CredentialStore(
            keychainManager: keychainManager,
            configLoader: { AppConfig(oauthGoogleClientId: "test-client") },
            oauthSession: session
        )
        let account = Account(
            id: accountId,
            label: "Work",
            emailAddress: "user@example.com",
            displayName: "User",
            authMethod: .oauth2(provider: .google),
            imapHost: "imap.example.com",
            smtpHost: "smtp.example.com"
        )

        let credentials = try await store.credentialsFor(account: account)
        switch credentials {
        case .oauth2(let tokenProvider):
            let accessToken = try await tokenProvider.accessToken()
            #expect(accessToken == "fresh-token")
        case .password:
            Issue.record("Expected an OAuth credential")
        }

        let storedTokens = await keychainManager.getOAuthTokens(accountId: accountId)
        #expect(storedTokens?.accessToken == "fresh-token")
        #expect(storedTokens?.refreshToken == "refresh-token")
    }

    @Test func calDAVRequestsUseLatestOAuthToken() async throws {
        let session = makeSession()
        let tokenSequence = TokenSequence(tokens: ["token-1", "token-2"])

        MockOAuthURLProtocol.enqueue { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/principals/user/"
                )
            )
        }
        MockOAuthURLProtocol.enqueue { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-2")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "calendar-home-set",
                    href: "/calendars/user/"
                )
            )
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://calendar.example.com/dav")!,
            credential: .oauthToken(OAuthTokenProvider {
                try await tokenSequence.next()
            }),
            session: session
        )

        try await client.authenticate()
    }

    @Test func authorizationCodeExchangeIncludesPKCEVerifier() async throws {
        let session = makeSession()
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-pkce.\(UUID().uuidString)")
        let manager = OAuth2Manager(keychainManager: keychainManager, session: session)
        let pkce = OAuth2Manager.generatePKCEChallenge()
        let redirectURI = "http://127.0.0.1:12345/oauth/callback"

        await manager.setConfig(
            OAuthConfig(
                clientId: "google-client",
                clientSecret: nil,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: ["https://mail.google.com/"],
                redirectURI: redirectURI
            ),
            for: .google
        )

        MockOAuthURLProtocol.enqueue { request in
            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=authorization_code"))
            #expect(body.contains("code=auth-code"))
            #expect(body.contains("client_id=google-client"))
            #expect(body.contains("code_verifier=\(pkce.verifier)"))

            return self.response(
                url: request.url!,
                status: 200,
                body: """
                {"access_token":"fresh-token","refresh_token":"refresh-token","expires_in":3600}
                """
            )
        }

        let tokens = try await manager.exchangeCodeForTokens(
            code: "auth-code",
            provider: .google,
            redirectURI: redirectURI,
            codeVerifier: pkce.verifier
        )

        #expect(tokens.accessToken == "fresh-token")
        #expect(tokens.refreshToken == "refresh-token")
    }

    @Test func authorizationCodeExchangeCapturesGrantedScopes() async throws {
        let session = makeSession()
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-granted-scopes.\(UUID().uuidString)")
        let manager = OAuth2Manager(keychainManager: keychainManager, session: session)
        let redirectURI = "http://127.0.0.1:12345/oauth/callback"

        await manager.setConfig(
            OAuthConfig(
                clientId: "google-client",
                clientSecret: nil,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: [
                    "https://mail.google.com/",
                    "https://www.googleapis.com/auth/calendar",
                    "https://www.googleapis.com/auth/carddav",
                ],
                redirectURI: redirectURI
            ),
            for: .google
        )

        MockOAuthURLProtocol.enqueue { request in
            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=authorization_code"))

            return self.response(
                url: request.url!,
                status: 200,
                body: """
                {"access_token":"fresh-token","refresh_token":"refresh-token","expires_in":3600,"scope":"https://mail.google.com/ https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/carddav"}
                """
            )
        }

        let tokens = try await manager.exchangeCodeForTokens(
            code: "auth-code",
            provider: .google,
            redirectURI: redirectURI
        )

        #expect(tokens.grantedScopes == [
            "https://mail.google.com/",
            "https://www.googleapis.com/auth/calendar",
            "https://www.googleapis.com/auth/carddav",
        ])
        #expect(tokens.grantsScope("https://www.googleapis.com/auth/calendar") == true)
        #expect(tokens.grantsScope("https://www.googleapis.com/auth/carddav") == true)
    }

    @Test func authorizationCodeExchangeCapturesAuthorizedGoogleEmailFromIDToken() async throws {
        let session = makeSession()
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-id-token.\(UUID().uuidString)")
        let manager = OAuth2Manager(keychainManager: keychainManager, session: session)
        let redirectURI = "http://127.0.0.1:12345/oauth/callback"

        await manager.setConfig(
            OAuthConfig(
                clientId: "google-client",
                clientSecret: nil,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: [
                    "openid",
                    "email",
                    "https://mail.google.com/",
                    "https://www.googleapis.com/auth/carddav",
                ],
                redirectURI: redirectURI
            ),
            for: .google
        )

        MockOAuthURLProtocol.enqueue { request in
            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=authorization_code"))

            return self.response(
                url: request.url!,
                status: 200,
                body: """
                {"access_token":"fresh-token","refresh_token":"refresh-token","expires_in":3600,"id_token":"\(self.mockGoogleIDToken(clientId: "google-client", email: "authorized@gmail.com", subject: "google-subject-123"))"}
                """
            )
        }

        let tokens = try await manager.exchangeCodeForTokens(
            code: "auth-code",
            provider: .google,
            redirectURI: redirectURI
        )

        #expect(tokens.authorizedEmail == "authorized@gmail.com")
        #expect(tokens.identity?.subject == "google-subject-123")
        #expect(tokens.identity?.emailVerified == true)
    }

    @Test func authorizationCodeExchangeIncludesClientSecretWhenConfigured() async throws {
        let session = makeSession()
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-client-secret.\(UUID().uuidString)")
        let manager = OAuth2Manager(keychainManager: keychainManager, session: session)
        let redirectURI = "http://127.0.0.1:12345/oauth/callback"

        await manager.setConfig(
            OAuthConfig(
                clientId: "google-client",
                clientSecret: "desktop-secret",
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: ["https://mail.google.com/"],
                redirectURI: redirectURI
            ),
            for: .google
        )

        MockOAuthURLProtocol.enqueue { request in
            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=authorization_code"))
            #expect(body.contains("code=auth-code"))
            #expect(body.contains("client_id=google-client"))
            #expect(body.contains("client_secret=desktop-secret"))

            return self.response(
                url: request.url!,
                status: 200,
                body: """
                {"access_token":"fresh-token","refresh_token":"refresh-token","expires_in":3600}
                """
            )
        }

        let tokens = try await manager.exchangeCodeForTokens(
            code: "auth-code",
            provider: .google,
            redirectURI: redirectURI
        )

        #expect(tokens.accessToken == "fresh-token")
        #expect(tokens.refreshToken == "refresh-token")
    }

    @Test func authorizationURLIncludesPKCEChallenge() async throws {
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-pkce-url.\(UUID().uuidString)")
        let manager = OAuth2Manager(keychainManager: keychainManager)
        let pkce = OAuth2Manager.generatePKCEChallenge()

        await manager.setConfig(
            OAuthConfig(
                clientId: "google-client",
                clientSecret: nil,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: ["https://mail.google.com/"],
                redirectURI: "http://127.0.0.1:54321/oauth/callback"
            ),
            for: .google
        )

        let url = try await manager.buildAuthorizationURL(
            provider: .google,
            state: "state-123",
            codeChallenge: pkce.challenge
        )
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map {
            ($0.name, $0.value ?? "")
        } ?? [])

        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["state"] == "state-123")
    }

    @Test func authorizationURLIncludesGoogleLoginHint() async throws {
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-login-hint.\(UUID().uuidString)")
        let manager = OAuth2Manager(keychainManager: keychainManager)

        await manager.setConfig(
            OAuthConfig(
                clientId: "google-client",
                clientSecret: nil,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: ["openid", "email", "https://mail.google.com/"],
                redirectURI: "http://127.0.0.1:54321/oauth/callback"
            ),
            for: .google
        )

        let url = try await manager.buildAuthorizationURL(
            provider: .google,
            state: "state-123",
            loginHint: " user@gmail.com "
        )
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map {
            ($0.name, $0.value ?? "")
        } ?? [])

        #expect(items["login_hint"] == "user@gmail.com")
    }

    @Test func refreshPreservesStoredIdentityWhenRefreshResponseOmitsIDToken() async throws {
        let session = makeSession()
        let accountId = UUID()
        let keychainManager = KeychainManager(serviceName: "com.clawmail.tests.oauth-refresh-identity.\(UUID().uuidString)")
        defer {
            Task {
                try? await keychainManager.deleteAll(accountId: accountId)
            }
        }
        let manager = OAuth2Manager(keychainManager: keychainManager, session: session)

        await manager.setConfig(
            OAuthConfig(
                clientId: "google-client",
                clientSecret: nil,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: ["openid", "email", "https://mail.google.com/"],
                redirectURI: "http://127.0.0.1:54321/oauth/callback"
            ),
            for: .google
        )

        try await keychainManager.saveOAuthTokens(
            accountId: accountId,
            tokens: OAuthTokens(
                accessToken: "stale-token",
                refreshToken: "refresh-token",
                expiresAt: .distantPast,
                grantedScopes: ["https://mail.google.com/"],
                identity: OAuthIdentity(subject: "google-subject-123", email: "authorized@gmail.com", emailVerified: true)
            )
        )

        MockOAuthURLProtocol.enqueue { request in
            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=refresh_token"))

            return self.response(
                url: request.url!,
                status: 200,
                body: """
                {"access_token":"fresh-token","expires_in":3600}
                """
            )
        }

        let accessToken = try await manager.refreshAccessToken(
            accountId: accountId,
            refreshToken: "refresh-token",
            provider: .google
        )

        #expect(accessToken == "fresh-token")
        let storedTokens = await keychainManager.getOAuthTokens(accountId: accountId)
        #expect(storedTokens?.authorizedEmail == "authorized@gmail.com")
        #expect(storedTokens?.identity?.subject == "google-subject-123")
        #expect(storedTokens?.grantedScopes == ["https://mail.google.com/"])
    }

    private func makeSession() -> URLSession {
        MockOAuthURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockOAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(url: URL, status: Int = 207, body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }

    private func multistatusBody(property: String, href: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat>
              <d:prop>
                <d:\(property)>
                  <d:href>\(href)</d:href>
                </d:\(property)>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
    }

    private func mockGoogleIDToken(clientId: String, email: String, subject: String) -> String {
        let header = #"{"alg":"none","typ":"JWT"}"#
        let payload = """
        {"iss":"https://accounts.google.com","aud":"\(clientId)","sub":"\(subject)","email":"\(email)","email_verified":true}
        """
        return "\(base64URLEncode(header))\(Character("."))\(base64URLEncode(payload))\(Character("."))signature"
    }
}

private func requestBody(for request: URLRequest) -> Data {
    if let httpBody = request.httpBody {
        return httpBody
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        guard bytesRead > 0 else { break }
        data.append(buffer, count: bytesRead)
    }
    return data
}

private actor TokenSequence {
    private var tokens: [String]

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func next() throws -> String {
        guard !tokens.isEmpty else {
            throw ClawMailError.serverError("No more test tokens available")
        }
        return tokens.removeFirst()
    }
}

private func base64URLEncode(_ rawValue: String) -> String {
    Data(rawValue.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private final class MockOAuthURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [@Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers = []
    }

    static func enqueue(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
        Self.lock.lock()
        handler = Self.handlers.isEmpty ? nil : Self.handlers.removeFirst()
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: ClawMailError.serverError("No mock response configured"))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
