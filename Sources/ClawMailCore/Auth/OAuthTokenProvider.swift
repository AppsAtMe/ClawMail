import Foundation

/// Lightweight wrapper for fetching the current OAuth access token on demand.
public struct OAuthTokenProvider: Sendable {
    private let fetchToken: @Sendable () async throws -> String

    public init(fetchToken: @escaping @Sendable () async throws -> String) {
        self.fetchToken = fetchToken
    }

    public func accessToken() async throws -> String {
        try await fetchToken()
    }

    public static func constant(_ accessToken: String) -> OAuthTokenProvider {
        OAuthTokenProvider { accessToken }
    }
}
