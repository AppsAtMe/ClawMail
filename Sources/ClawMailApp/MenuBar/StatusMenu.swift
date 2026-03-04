import SwiftUI
import ClawMailCore

/// SwiftUI view for the menu bar dropdown menu.
struct StatusMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Service status
            if let error = appState.launchError {
                Label("Error: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else if appState.isRunning {
                Label("ClawMail is running", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                Label("Starting...", systemImage: "hourglass")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            Divider()

            // Account status
            if appState.accounts.isEmpty {
                Text("No accounts configured")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(appState.accounts) { account in
                    HStack(spacing: 6) {
                        statusDot(for: account.connectionStatus)
                        Text(account.label)
                        Spacer()
                        Text(account.emailAddress)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }
            }

            // Agent status
            if appState.agentConnected {
                Divider()
                Label("Agent connected", systemImage: "link.circle.fill")
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            if let activity = appState.lastActivity {
                Text("Last: \(activity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }

            Divider()

            // Actions
            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Activity Log...") {
                appState.settingsTab = .activityLog
                openSettings()
            }

            Divider()

            Button("Quit ClawMail") {
                // Use exit() as fallback if terminate hangs due to stuck NIO connections
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    exit(0)
                }
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func openSettings() {
        openSettingsAction()
        NSApp.activate(ignoringOtherApps: true)
    }

    @ViewBuilder
    private func statusDot(for status: ConnectionStatus) -> some View {
        Circle()
            .fill(statusColor(for: status))
            .frame(width: 8, height: 8)
    }

    private func statusColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
