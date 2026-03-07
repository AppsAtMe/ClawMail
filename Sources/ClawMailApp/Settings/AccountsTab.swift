import SwiftUI
import ClawMailCore

/// Accounts settings tab: list of configured accounts with add/remove/edit.
struct AccountsTab: View {
    internal let inspection = Inspection<Self>()
    @Environment(AppState.self) private var environmentAppState
    private let appStateOverride: AppState?
    private let removeAccountAction: @MainActor (AppState, Account) async throws -> Void
    private let initialSelectedAccountId: UUID?
    @State private var setupController = SetupSheetController()
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
        self.initialSelectedAccountId = initialSelectedAccountId
        _errorState = State(initialValue: initialErrorState)
    }

    var body: some View {
        @Bindable var state = appState

        HStack(spacing: 0) {
            // Account list sidebar
            VStack(spacing: 0) {
                List(selection: $state.selectedSettingsAccountID) {
                    ForEach(appState.accounts) { account in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.label)
                                    .font(.headline)
                                Text(account.emailAddress)
                                    .font(.caption)
                                    .foregroundStyle(Color.primary.opacity(0.72))
                            }
                            Spacer()
                            ConnectionStatusBadge(status: account.connectionStatus)
                        }
                        .tag(account.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(action: beginAddAccount) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add Account")

                    Button(action: beginEditSelectedAccount) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedAccount == nil)
                    .help("Edit Account")

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
                AccountDetailView(account: account, onEdit: beginEditSelectedAccount)
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
        .sheet(item: Binding(
            get: { setupController.session },
            set: { setupController.session = $0 }
        )) { session in
            AccountSetupView(mode: session.mode)
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
        .onAppear {
            presentSetupIfNeeded()
            ensureAccountSelection(preferred: initialSelectedAccountId)
        }
        .onChange(of: appState.showAccountSetup) { _, _ in
            presentSetupIfNeeded()
        }
        .onChange(of: appState.accounts.map(\.id)) { _, _ in
            ensureAccountSelection(preferred: initialSelectedAccountId)
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }

    private var selectedAccount: Account? {
        appState.accounts.first { $0.id == appState.selectedSettingsAccountID }
    }

    private var appState: AppState {
        appStateOverride ?? environmentAppState
    }

    private func removeAccount(_ account: Account) {
        Task {
            do {
                try await removeAccountAction(appState, account)
                await appState.refreshAccounts()
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

    private func presentSetupIfNeeded() {
        setupController.presentQueuedAddIfNeeded(showAccountSetup: &appState.showAccountSetup)
    }

    private func ensureAccountSelection(preferred preferredID: UUID? = nil) {
        appState.ensureSelectedSettingsAccount(preferred: preferredID)
    }

    private func beginAddAccount() {
        setupController.presentAdd()
    }

    private func beginEditSelectedAccount() {
        setupController.presentEdit(account: selectedAccount)
    }
}

internal struct SetupSheetSession: Identifiable, Equatable {
    let id = UUID()
    let mode: AccountSetupMode
}

internal struct SetupSheetController {
    var session: SetupSheetSession?

    mutating func presentQueuedAddIfNeeded(showAccountSetup: inout Bool) {
        guard showAccountSetup, session == nil else { return }
        showAccountSetup = false
        presentAdd()
    }

    mutating func presentAdd() {
        session = SetupSheetSession(mode: .add)
    }

    mutating func presentEdit(account: Account?) {
        guard let account else { return }
        session = SetupSheetSession(mode: .edit(account))
    }
}

// MARK: - Account Detail View

struct AccountDetailView: View {
    @Environment(AppState.self) private var appState
    let account: Account
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(account.label)
                    .font(.title2.bold())
                Spacer()
                Button("Edit Account...", action: onEdit)
            }
            .padding(.horizontal)
            .padding(.top)

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
                        VStack(alignment: .trailing, spacing: 4) {
                            ConnectionStatusBadge(status: account.connectionStatus)
                            if case .error(let message) = account.connectionStatus {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    if let lastSync = account.lastSyncDate {
                        LabeledContent("Last Sync", value: lastSync.formatted())
                    }
                    LabeledContent("Enabled", value: account.isEnabled ? "Yes" : "No")
                    LabeledContent("Recent Activity") {
                        Text(appState.accountActivity[account.label] ?? "Waiting for activity...")
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    private var authMethodText: String {
        switch account.authMethod {
        case .password: return "Password"
        case .oauth2(let provider): return "OAuth2 (\(provider.displayName))"
        }
    }
}
