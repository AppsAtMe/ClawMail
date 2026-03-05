import SwiftUI
import ClawMailCore
import Security

/// OAuth2 flow UI: shown during Google/Microsoft OAuth authorization.
///
/// Implements the full Authorization Code flow:
/// 1. Generate cryptographic `state` parameter (CSRF prevention, RFC 6749 §10.12)
/// 2. Start a local HTTP callback server on 127.0.0.1 (random port)
/// 3. Open the user's browser to the authorization URL
/// 4. Wait for the provider to redirect back with `code` and `state`
/// 5. Validate that `state` matches (prevents OAuth CSRF attacks)
/// 6. Exchange the code for access + refresh tokens
/// 7. Save tokens to Keychain
struct OAuthFlowView: View {
    @Environment(AppState.self) private var appState

    let provider: OAuthProvider
    @Binding var inProgress: Bool
    /// Called with the obtained tokens after a successful OAuth flow.
    var onTokensObtained: ((OAuthTokens) -> Void)?

    @State private var status: OAuthStatus = .waiting
    @State private var errorMessage: String?
    @State private var callbackServer: OAuthCallbackServer?

    enum OAuthStatus {
        case waiting
        case browserOpened
        case completed
        case failed
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Sign in with \(provider.rawValue.capitalized)")
                .font(.title3.bold())

            switch status {
            case .waiting:
                VStack(spacing: 12) {
                    Text("Click below to open your browser and sign in.")
                        .foregroundStyle(.secondary)

                    Button("Open Browser") {
                        startOAuthFlow()
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .browserOpened:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)

                    Text("Waiting for authorization...")
                        .foregroundStyle(.secondary)

                    Text("Complete the sign-in in your browser.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("Cancel") {
                        cancelFlow()
                    }
                }

            case .completed:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text("Authorization successful!")
                }

            case .failed:
                VStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.red)
                    Text(errorMessage ?? "Authorization failed.")
                    Button("Try Again") {
                        status = .waiting
                        errorMessage = nil
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - OAuth Flow

    private func startOAuthFlow() {
        // Validate that OAuth client IDs are configured before starting
        let clientId = oauthClientId(for: provider)
        guard !clientId.isEmpty else {
            status = .failed
            errorMessage = "OAuth client ID not configured for \(provider.rawValue.capitalized). Go to Settings → API → OAuth to enter your client ID."
            return
        }

        inProgress = true
        status = .browserOpened

        Task {
            do {
                // 1. Generate cryptographic state (CSRF prevention)
                let state = Self.generateState()

                // 2. Start local callback server on random port
                let server = OAuthCallbackServer()
                await MainActor.run { self.callbackServer = server }
                let (_, redirectURI) = try await server.start()

                // 3. Build authorization URL with the actual redirect URI
                let oauthManager = OAuth2Manager(keychainManager: KeychainManager())
                let config = Self.oauthConfig(for: provider, appConfig: appState.config, redirectURI: redirectURI)
                await oauthManager.setConfig(config, for: provider)

                let authURL = try await oauthManager.buildAuthorizationURL(provider: provider, state: state)

                // 4. Open the user's browser
                NSWorkspace.shared.open(authURL)

                // 5. Wait for the callback (2-minute timeout)
                let result = try await server.waitForCallback(timeout: .seconds(120))

                // 6. Validate state — prevents CSRF attacks (RFC 6749 §10.12)
                guard Self.constantTimeEqual(result.state, state) else {
                    throw ClawMailError.authFailed(
                        "OAuth state mismatch — possible CSRF attack. Please try again."
                    )
                }

                // 7. Exchange authorization code for tokens
                let tokens = try await oauthManager.exchangeCodeForTokens(
                    code: result.code,
                    provider: provider,
                    redirectURI: redirectURI
                )

                // 8. Clean up server
                await server.stop()

                // 9. Report success
                await MainActor.run {
                    self.callbackServer = nil
                    self.status = .completed
                    self.inProgress = false
                    self.onTokensObtained?(tokens)
                }

            } catch {
                // Clean up on failure
                if let server = await MainActor.run(body: { self.callbackServer }) {
                    await server.stop()
                }
                await MainActor.run {
                    self.callbackServer = nil
                    self.status = .failed
                    self.errorMessage = String(describing: error)
                    self.inProgress = false
                }
            }
        }
    }

    private func cancelFlow() {
        Task {
            if let server = callbackServer {
                await server.stop()
            }
            await MainActor.run {
                callbackServer = nil
                status = .waiting
                inProgress = false
            }
        }
    }

    // MARK: - Helpers

    /// Returns the configured OAuth client ID for the given provider.
    private func oauthClientId(for provider: OAuthProvider) -> String {
        switch provider {
        case .google: return appState.config.oauthGoogleClientId ?? ""
        case .microsoft: return appState.config.oauthMicrosoftClientId ?? ""
        }
    }

    /// Build OAuthConfig with the actual redirect URI (includes the callback server's port).
    private static func oauthConfig(for provider: OAuthProvider, appConfig: AppConfig, redirectURI: String) -> OAuthConfig {
        switch provider {
        case .google:
            return OAuthConfig(
                clientId: appConfig.oauthGoogleClientId ?? "",
                clientSecret: appConfig.oauthGoogleClientSecret,
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: [
                    "https://mail.google.com/",
                    "https://www.googleapis.com/auth/calendar",
                    "https://www.googleapis.com/auth/contacts",
                ],
                redirectURI: redirectURI
            )
        case .microsoft:
            return OAuthConfig(
                clientId: appConfig.oauthMicrosoftClientId ?? "",
                clientSecret: appConfig.oauthMicrosoftClientSecret,
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
                redirectURI: redirectURI
            )
        }
    }

    /// Generate a 32-byte cryptographically random state parameter, hex-encoded.
    private static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time string comparison to prevent timing attacks on state validation.
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(aBytes, bBytes) {
            result |= x ^ y
        }
        return result == 0
    }
}

