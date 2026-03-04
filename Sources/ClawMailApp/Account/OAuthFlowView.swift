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

        // In a full implementation, this would use OAuth2Manager to:
        // 1. Generate the authorization URL
        // 2. Open the browser
        // 3. Start a local HTTP listener for the callback
        // 4. Exchange the code for tokens
        // 5. Save tokens to keychain
        // For now, this is a placeholder that shows the flow structure.

        // Placeholder: In a full implementation, this would use OAuth2Manager to:
        // 1. Generate the authorization URL
        // 2. Open the browser via NSWorkspace
        // 3. Start a local HTTP listener for the callback
        // 4. Exchange the code for tokens
        // 5. Save tokens to keychain
        // For now, mark as completed after a delay to show the flow structure.
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                status = .completed
                inProgress = false
            }
        }
    }
}
