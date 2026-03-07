import SwiftUI
import ClawMailCore

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
            Text("Sign in with \(provider.displayName)")
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
        let clientId = OAuthHelpers.oauthClientId(for: provider, appConfig: appState.config)
        guard !clientId.isEmpty else {
            status = .failed
            errorMessage = "OAuth client ID not configured for \(provider.displayName). Go to Settings → API → OAuth to enter your client ID."
            return
        }

        inProgress = true
        status = .browserOpened

        Task {
            do {
                // 1. Generate cryptographic state (CSRF prevention)
                let state = OAuthHelpers.generateState()

                // 2. Start local callback server on random port
                let server = OAuthCallbackServer()
                await MainActor.run { self.callbackServer = server }
                let (_, redirectURI) = try await server.start()

                // 3. Build authorization URL with the actual redirect URI
                let km = KeychainManager()
                let secret = await km.getOAuthClientSecret(for: provider)
                let oauthManager = OAuth2Manager(keychainManager: km)
                let config = OAuthHelpers.oauthConfig(
                    for: provider,
                    appConfig: appState.config,
                    clientSecret: secret,
                    redirectURI: redirectURI
                )
                await oauthManager.setConfig(config, for: provider)

                let authURL = try await oauthManager.buildAuthorizationURL(provider: provider, state: state)

                // 4. Open the user's browser
                NSWorkspace.shared.open(authURL)

                // 5. Wait for the callback (2-minute timeout)
                let result = try await server.waitForCallback(timeout: .seconds(120))

                // 6. Validate state — prevents CSRF attacks (RFC 6749 §10.12)
                guard OAuthHelpers.constantTimeEqual(result.state, state) else {
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
}
