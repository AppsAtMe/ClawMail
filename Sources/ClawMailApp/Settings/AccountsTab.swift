import SwiftUI
import ClawMailCore

/// Accounts settings tab: list of configured accounts with add/remove/edit.
struct AccountsTab: View {
    @Environment(AppState.self) private var appState
    @State private var selectedAccountId: UUID?
    @State private var showingSetup = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            // Account list sidebar
            VStack(spacing: 0) {
                List(selection: $selectedAccountId) {
                    ForEach(appState.accounts) { account in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(for: account.connectionStatus))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(account.label)
                                    .font(.headline)
                                Text(account.emailAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(account.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(action: { showingSetup = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add Account")

                    Button(action: { showingDeleteConfirm = true }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedAccount == nil)
                    .help("Remove Account")

                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 220)

            Divider()

            // Account detail
            if let account = selectedAccount {
                AccountDetailView(account: account)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "person.crop.circle",
                    description: Text("Select an account or click + to add one.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingSetup) {
            AccountSetupView()
                .environment(appState)
        }
        .alert("Remove Account", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let account = selectedAccount {
                    removeAccount(account)
                }
            }
        } message: {
            if let account = selectedAccount {
                Text("Remove \"\(account.label)\"? This will disconnect the account and remove its local data.")
            }
        }
    }

    private var selectedAccount: Account? {
        appState.accounts.first { $0.id == selectedAccountId }
    }

    private func removeAccount(_ account: Account) {
        Task {
            try? await appState.orchestrator?.removeAccount(label: account.label)
            await appState.refreshAccounts()
            selectedAccountId = nil
        }
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

// MARK: - Account Detail View

struct AccountDetailView: View {
    let account: Account

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Label", value: account.label)
                LabeledContent("Email", value: account.emailAddress)
                LabeledContent("Display Name", value: account.displayName)
                LabeledContent("Auth", value: authMethodText)
            }

            Section("IMAP") {
                LabeledContent("Host", value: account.imapHost)
                LabeledContent("Port", value: "\(account.imapPort)")
                LabeledContent("Security", value: account.imapSecurity.rawValue.uppercased())
            }

            Section("SMTP") {
                LabeledContent("Host", value: account.smtpHost)
                LabeledContent("Port", value: "\(account.smtpPort)")
                LabeledContent("Security", value: account.smtpSecurity.rawValue.uppercased())
            }

            if let caldav = account.caldavURL {
                Section("CalDAV") {
                    LabeledContent("URL", value: caldav.absoluteString)
                }
            }

            if let carddav = account.carddavURL {
                Section("CardDAV") {
                    LabeledContent("URL", value: carddav.absoluteString)
                }
            }

            Section("Status") {
                LabeledContent("Connection") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                    }
                }
                if let lastSync = account.lastSyncDate {
                    LabeledContent("Last Sync", value: lastSync.formatted())
                }
                LabeledContent("Enabled", value: account.isEnabled ? "Yes" : "No")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var authMethodText: String {
        switch account.authMethod {
        case .password: return "Password"
        case .oauth2(let provider): return "OAuth2 (\(provider.rawValue))"
        }
    }

    private var statusText: String {
        switch account.connectionStatus {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var statusColor: Color {
        switch account.connectionStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
