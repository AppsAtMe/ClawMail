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
