import SwiftUI
import ClawMailCore

/// Accounts settings tab: list of configured accounts with add/remove/edit.
struct AccountsTab: View {
    @Environment(AppState.self) private var environmentAppState
    private let appStateOverride: AppState?
    private let removeAccountAction: @MainActor (AppState, Account) async throws -> Void
    @State private var selectedAccountId: UUID?
    @State private var showingSetup = false
    @State private var showingDeleteConfirm = false
    @State private var errorState: UIErrorState?

    init(
        appState: AppState? = nil,
        initialSelectedAccountId: UUID? = nil,
        initialErrorState: UIErrorState? = nil,
        removeAccountAction: @escaping @MainActor (AppState, Account) async throws -> Void = Self.defaultRemoveAccountAction
    ) {
        self.appStateOverride = appState
        self.removeAccountAction = removeAccountAction
        _selectedAccountId = State(initialValue: initialSelectedAccountId)
        _errorState = State(initialValue: initialErrorState)
    }

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
        .alert("Operation Failed", isPresented: showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorState?.message ?? "Unknown error.")
        }
    }

    private var selectedAccount: Account? {
        appState.accounts.first { $0.id == selectedAccountId }
    }

    private var appState: AppState {
        appStateOverride ?? environmentAppState
    }

    private func removeAccount(_ account: Account) {
        Task {
            do {
                try await removeAccountAction(appState, account)
                await appState.refreshAccounts()
                await MainActor.run {
                    selectedAccountId = nil
                }
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Removing account", error: error)
                }
            }
        }
    }

    private var showingErrorAlert: Binding<Bool> {
        Binding(
            get: { errorState != nil },
            set: { if !$0 { errorState = nil } }
        )
    }

    private static func defaultRemoveAccountAction(appState: AppState, account: Account) async throws {
        try await appState.orchestrator?.removeAccount(label: account.label)
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
