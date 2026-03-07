import SwiftUI
import ClawMailCore

/// SwiftUI view for the menu bar dropdown menu.
struct StatusMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerCard

            if appState.accounts.isEmpty {
                emptyAccountsCard
            } else {
                ForEach(appState.accounts) { account in
                    Button(action: { openAccounts(accountID: account.id) }) {
                        accountCard(account)
                    }
                    .buttonStyle(.plain)
                }
            }

            if appState.agentConnected {
                automationCard
            }

            if shouldShowGlobalActivity, let activity = appState.lastActivity {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Activity")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(activity)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.82))
                }
                .padding(.horizontal, 2)
            }

            Divider()

            VStack(spacing: 8) {
                Button(action: openSettings) {
                    actionRow("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)

                Button(action: openActivityLog) {
                    actionRow("Activity Log", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)

                Button(action: quitApp) {
                    actionRow("Quit ClawMail", systemImage: "power")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func openSettings() {
        openSettingsAction()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openActivityLog() {
        appState.settingsTab = .activityLog
        openSettings()
    }

    private func openAccounts(accountID: UUID? = nil) {
        appState.focusSettingsAccount(accountID)
        openSettings()
    }

    private func quitApp() {
        // Use exit() as fallback if terminate hangs due to stuck NIO connections
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            exit(0)
        }
        NSApplication.shared.terminate(nil)
    }

    private var headerCard: some View {
        Button(action: openActivityLog) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "envelope.badge")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(headerTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ClawMail")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(Color.primary.opacity(0.72))
                    }
                    Spacer(minLength: 10)
                    serviceBadge(headerBadgeTitle, systemImage: headerBadgeIcon, tint: headerTint, usesDarkText: headerUsesDarkText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyAccountsCard: some View {
        Button(action: {
            appState.showAccountSetup = true
            openAccounts()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("No accounts configured")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                Text("Add your first account to start syncing mail, calendar, contacts, and tasks.")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func accountCard(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.label)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(account.emailAddress)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
                Spacer(minLength: 10)
                ConnectionStatusBadge(status: account.connectionStatus)
            }

            Text(accountActivityText(for: account))
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.82))
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(statusTint(for: account.connectionStatus).opacity(0.12))
        )
    }

    private var automationCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Automation")
                    .font(.subheadline.weight(.semibold))
                Text("Agent connected")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.72))
            }
            Spacer()
            serviceBadge("Connected", systemImage: "checkmark", tint: .blue)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(0.10))
        )
    }

    private func actionRow(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var shouldShowGlobalActivity: Bool {
        guard let lastActivity = appState.lastActivity else { return false }
        return !appState.accountActivity.values.contains(lastActivity)
    }

    private func accountActivityText(for account: Account) -> String {
        if let activity = appState.accountActivity[account.label] {
            return activity
        }

        switch account.connectionStatus {
        case .connected:
            return "Connected and ready."
        case .connecting:
            return "Connecting to this account now."
        case .disconnected:
            return "Not currently connected."
        case .error(let message):
            return message
        }
    }

    private var headerBadgeTitle: String {
        if appState.launchError != nil {
            return "Error"
        }
        return appState.isRunning ? "Running" : "Starting"
    }

    private var headerBadgeIcon: String {
        if appState.launchError != nil {
            return "exclamationmark.triangle.fill"
        }
        return appState.isRunning ? "checkmark.circle.fill" : "hourglass"
    }

    private var headerSubtitle: String {
        if let error = appState.launchError {
            return error
        }
        let connectedAccounts = appState.accounts.filter {
            if case .connected = $0.connectionStatus { return true }
            return false
        }.count
        let noun = connectedAccounts == 1 ? "account" : "accounts"
        return "\(connectedAccounts) \(noun) ready"
    }

    private var headerTint: Color {
        if appState.launchError != nil {
            return .red
        }
        return appState.isRunning ? .green : .orange
    }

    private var headerUsesDarkText: Bool {
        appState.launchError == nil && !appState.isRunning
    }

    private func statusTint(for status: ConnectionStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .secondary
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private func serviceBadge(_ title: String, systemImage: String, tint: Color, usesDarkText: Bool = false) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(usesDarkText ? Color.black.opacity(0.82) : .white)
            .background(
                Capsule()
                    .fill(tint)
            )
    }
}
