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
    let loginHint: String?
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

                    if let hint = providerSetupHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

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

                    if let hint = providerWaitingHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

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
            errorMessage = missingClientIDMessage(for: provider)
            return
        }

        inProgress = true
        status = .browserOpened

        Task {
            do {
                // 1. Generate cryptographic state (CSRF prevention)
                let state = OAuthHelpers.generateState()
                let pkce = OAuth2Manager.generatePKCEChallenge()

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

                let authURL = try await oauthManager.buildAuthorizationURL(
                    provider: provider,
                    state: state,
                    codeChallenge: pkce.challenge,
                    loginHint: loginHint
                )

                logOAuthDebug(
                    "Authorization request scopes: \(config.scopes.joined(separator: ", "))"
                )
                logOAuthDebug(
                    "Authorization URL (redacted): \(redactedAuthorizationURL(authURL))"
                )

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
                    redirectURI: redirectURI,
                    codeVerifier: pkce.verifier
                )

                if let grantedScopes = tokens.grantedScopes, !grantedScopes.isEmpty {
                    logOAuthDebug(
                        "Token exchange granted scopes: \(grantedScopes.joined(separator: ", "))"
                    )
                } else {
                    logOAuthDebug("Token exchange did not include a scope list in the response.")
                }
                if let authorizedEmail = tokens.authorizedEmail {
                    logOAuthDebug("Token exchange authorized email: \(authorizedEmail)")
                }

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
                    self.inProgress = false
                    if error is CancellationError {
                        self.status = .waiting
                        self.errorMessage = nil
                    } else {
                        self.status = .failed
                        self.errorMessage = self.userVisibleOAuthError(error)
                    }
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
                errorMessage = nil
                inProgress = false
            }
        }
    }

    private func missingClientIDMessage(for provider: OAuthProvider) -> String {
        switch provider {
        case .google:
            return "Google OAuth client ID not configured. Create a Desktop app OAuth client in Google Cloud Console, then paste its Client ID into Settings → API → OAuth Client IDs."
        case .microsoft:
            return "Microsoft OAuth client ID not configured. Create an app registration in Microsoft Entra, then paste its Application (client) ID into Settings → API → OAuth Client IDs."
        }
    }

    private var providerSetupHint: String? {
        switch provider {
        case .google:
            return "Google Cloud setup note: if your OAuth consent screen is in Testing, add your Google account as a test user before trying browser sign-in. If a personal Gmail address is rejected as ineligible, check that the project Audience is set to External. In Google Auth platform > Data Access, make sure the Gmail, Calendar, and Google CardDAV scope `https://www.googleapis.com/auth/carddav` are configured. Google's live CardDAV endpoint asked ClawMail for that exact scope. The authorized email field above fills in after browser sign-in confirms the account."
        case .microsoft:
            return "Microsoft setup note: the app registration should allow the Mobile and desktop applications platform with http://localhost."
        }
    }

    private var providerWaitingHint: String? {
        switch provider {
        case .google:
            return "If Google shows Error 403: access_denied, close that tab and check your OAuth consent screen, Audience setting, test-user list, Data Access scope list, and app verification settings."
        case .microsoft:
            return nil
        }
    }

    private func userVisibleOAuthError(_ error: Error) -> String {
        let baseMessage: String
        if let clawError = error as? ClawMailError {
            baseMessage = clawError.message
        } else {
            baseMessage = String(describing: error)
        }

        let normalized = baseMessage.lowercased()
        if provider == .google {
            if normalized.contains("client_secret is missing") {
                return "Google completed browser sign-in, but the token exchange rejected this OAuth client because no client secret was configured. Paste the Google Client Secret from the same OAuth client into Settings -> API -> OAuth Client IDs, then try again. If you already have one entered, recreate the Google OAuth client as a Desktop app and use the new Client ID + Client Secret pair."
            }
            if normalized.contains("access_denied") {
                return "Google denied the OAuth request. Make sure this is a Google Desktop app client, the project Audience is External if you are testing with a personal Gmail account, your Google account is added as a test user while the consent screen is in Testing, Google Auth platform > Data Access includes the Gmail, Calendar, and Google CardDAV scope `https://www.googleapis.com/auth/carddav` ClawMail requests, and be aware that the Gmail IMAP/SMTP scope used by ClawMail is a restricted Google scope."
            }
            if normalized.contains("timed out") {
                return "Google sign-in timed out. If the browser showed Error 403: access_denied, check that the project Audience is External for personal Gmail testing, add your Google account as a test user on the Google OAuth consent screen, and retry."
            }
        }

        return baseMessage
    }

    private func logOAuthDebug(_ message: String) {
        fputs("ClawMail OAuth (\(provider.rawValue)): \(message)\n", stderr)
    }

    private func redactedAuthorizationURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return url.absoluteString
        }

        components.queryItems = queryItems.map { item in
            switch item.name {
            case "state", "code_challenge", "login_hint":
                return URLQueryItem(name: item.name, value: "<redacted>")
            default:
                return item
            }
        }

        return components.string ?? url.absoluteString
    }
}
