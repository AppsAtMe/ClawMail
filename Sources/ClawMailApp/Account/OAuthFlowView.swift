import SwiftUI
import ClawMailCore

/// OAuth2 flow UI: shown during Google/Microsoft OAuth authorization.
struct OAuthFlowView: View {
    @Environment(AppState.self) private var appState

    let provider: OAuthProvider
    @Binding var inProgress: Bool

    @State private var status: OAuthStatus = .waiting
    @State private var errorMessage: String?

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

                    Button("Open Browser Again") {
                        startOAuthFlow()
                    }
                    .buttonStyle(.bordered)

                    Button("Cancel") {
                        status = .waiting
                        inProgress = false
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

    private func startOAuthFlow() {
        inProgress = true
        status = .browserOpened

        // PLACEHOLDER: Full OAuth implementation is tracked in ROADMAP.md.
        //
        // When implementing, the flow must:
        // 1. Generate a cryptographically random `state` parameter (use SecRandomCopyBytes)
        // 2. Include `state` in the authorization URL
        // 3. Start a local HTTP listener for the callback on 127.0.0.1
        // 4. On callback, VALIDATE that the returned `state` matches the one sent
        //    (this prevents CSRF attacks where a malicious site redirects the user
        //     with an attacker's authorization code)
        // 5. Exchange the code for tokens over HTTPS
        // 6. Save tokens to Keychain
        //
        // SECURITY: Omitting state validation enables OAuth CSRF attacks.
        // See: https://datatracker.ietf.org/doc/html/rfc6749#section-10.12
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                status = .completed
                inProgress = false
            }
        }
    }
}
