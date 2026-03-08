import Foundation
import Security

/// Pure helper functions for OAuth2 flows, extracted for testability.
/// These have no UI or environment dependencies.
public enum OAuthHelpers {

    /// Generate a 32-byte cryptographically random state parameter, hex-encoded.
    public static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time string comparison to prevent timing attacks on state validation.
    public static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(aBytes, bBytes) {
            result |= x ^ y
        }
        return result == 0
    }

    /// Build OAuthConfig. `clientSecret` is read from the Keychain by the caller and
    /// passed in so this function stays synchronous and independently testable.
    public static func oauthConfig(
        for provider: OAuthProvider,
        appConfig: AppConfig,
        clientSecret: String?,
        redirectURI: String
    ) -> OAuthConfig {
        switch provider {
        case .google:
            return OAuthConfig(
                clientId: appConfig.oauthGoogleClientId ?? "",
                clientSecret: clientSecret,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: [
                    "openid",
                    "email",
                    "https://mail.google.com/",
                    "https://www.googleapis.com/auth/calendar",
                    "https://www.googleapis.com/auth/carddav",
                ],
                redirectURI: redirectURI
            )
        case .microsoft:
            return OAuthConfig(
                clientId: appConfig.oauthMicrosoftClientId ?? "",
                clientSecret: clientSecret,
                authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
                tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
                scopes: [
                    "offline_access",
                    "https://outlook.office.com/IMAP.AccessAsUser.All",
                    "https://outlook.office.com/SMTP.Send",
                ],
                redirectURI: redirectURI
            )
        }
    }

    /// Returns the configured OAuth client ID for the given provider, or empty string if not set.
    public static func oauthClientId(for provider: OAuthProvider, appConfig: AppConfig) -> String {
        switch provider {
        case .google: return appConfig.oauthGoogleClientId ?? ""
        case .microsoft: return appConfig.oauthMicrosoftClientId ?? ""
        }
    }
}
