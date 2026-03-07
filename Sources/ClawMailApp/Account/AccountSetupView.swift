import SwiftUI
import ClawMailCore

// MARK: - Setup Step Enum

enum SetupStep: Int, CaseIterable {
    case provider, credentials, connectionTest, label, done
}

enum ProviderChoice: String, CaseIterable {
    case apple = "Apple / iCloud"
    case google = "Google"
    case microsoft = "Microsoft 365 / Outlook"
    case other = "Other Mail Account"

    static let defaultChoice: ProviderChoice = .apple

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "envelope.badge.person.crop"
        case .microsoft: return "envelope.badge.shield.half.filled"
        case .other: return "server.rack"
        }
    }

    var subtitle: String {
        switch self {
        case .apple:
            return "iCloud Mail, Calendar, Contacts, and Reminders with Apple's app-password setup"
        case .google:
            return "Browser sign-in with Google"
        case .microsoft:
            return "Browser sign-in with Microsoft"
        case .other:
            return "Manual IMAP and SMTP configuration"
        }
    }

    var oauthProvider: OAuthProvider? {
        switch self {
        case .google: return .google
        case .microsoft: return .microsoft
        case .apple, .other: return nil
        }
    }

    var usesOAuth: Bool {
        oauthProvider != nil
    }

    var authMethod: AuthMethod {
        if let oauthProvider {
            return .oauth2(provider: oauthProvider)
        }
        return .password
    }

    var serverSettings: ProviderServerSettings? {
        switch self {
        case .apple:
            return ProviderServerSettings(
                imapHost: "imap.mail.me.com",
                imapPort: "993",
                imapSecurity: .ssl,
                smtpHost: "smtp.mail.me.com",
                smtpPort: "587",
                smtpSecurity: .starttls
            )
        case .google:
            return ProviderServerSettings(
                imapHost: "imap.gmail.com",
                imapPort: "993",
                imapSecurity: .ssl,
                smtpHost: "smtp.gmail.com",
                smtpPort: "465",
                smtpSecurity: .ssl
            )
        case .microsoft:
            return ProviderServerSettings(
                imapHost: "outlook.office365.com",
                imapPort: "993",
                imapSecurity: .ssl,
                smtpHost: "smtp.office365.com",
                smtpPort: "587",
                smtpSecurity: .starttls
            )
        case .other:
            return nil
        }
    }

    var davSettings: ProviderDAVSettings? {
        switch self {
        case .apple:
            return ProviderDAVSettings(
                caldavURL: "https://caldav.icloud.com",
                carddavURL: "https://contacts.icloud.com"
            )
        case .google, .microsoft, .other:
            return nil
        }
    }

    static func inferred(from account: Account) -> ProviderChoice {
        switch account.authMethod {
        case .oauth2(.google):
            return .google
        case .oauth2(.microsoft):
            return .microsoft
        case .password:
            if account.imapHost.caseInsensitiveCompare("imap.mail.me.com") == .orderedSame,
               account.smtpHost.caseInsensitiveCompare("smtp.mail.me.com") == .orderedSame {
                return .apple
            }
            return .other
        }
    }
}

struct ProviderServerSettings: Equatable {
    let imapHost: String
    let imapPort: String
    let imapSecurity: ConnectionSecurity
    let smtpHost: String
    let smtpPort: String
    let smtpSecurity: ConnectionSecurity
}

struct ProviderDAVSettings: Equatable {
    let caldavURL: String
    let carddavURL: String
}

enum AccountSetupMode: Equatable {
    case add
    case edit(Account)

    var existingAccount: Account? {
        if case .edit(let account) = self {
            return account
        }
        return nil
    }

    var isEditing: Bool {
        existingAccount != nil
    }
}

// MARK: - Account Setup View

struct AccountSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let mode: AccountSetupMode

    @State private var step: SetupStep = .provider
    @State private var provider: ProviderChoice = ProviderChoice.defaultChoice
    @State private var emailAddress = ""
    @State private var displayName = ""
    @State private var imapHost = ""
    @State private var imapPort = "993"
    @State private var imapSecurity: ConnectionSecurity = .ssl
    @State private var smtpHost = ""
    @State private var smtpPort = "465"
    @State private var smtpSecurity: ConnectionSecurity = .ssl
    @State private var password = ""
    @State private var caldavURL = ""
    @State private var carddavURL = ""
    @State private var accountLabel = ""
    @State private var testInProgress = false
    @State private var testResults: [ConnectionTestResult] = []
    @State private var oauthInProgress = false
    @State private var oauthTokens: OAuthTokens?
    @State private var storedPassword: String?
    @State private var storedOAuthTokens: OAuthTokens?
    @State private var saveError: String?
    @State private var saveInProgress = false

    init(mode: AccountSetupMode = .add) {
        self.mode = mode

        let existingAccount = mode.existingAccount
        let inferredProvider = existingAccount.map(ProviderChoice.inferred(from:)) ?? ProviderChoice.defaultChoice
        let serverSettings = inferredProvider.serverSettings
        let davSettings = inferredProvider.davSettings

        _step = State(initialValue: mode.isEditing ? .credentials : .provider)
        _provider = State(initialValue: inferredProvider)
        _emailAddress = State(initialValue: existingAccount?.emailAddress ?? "")
        _displayName = State(initialValue: existingAccount?.displayName ?? "")
        _imapHost = State(initialValue: existingAccount?.imapHost ?? serverSettings?.imapHost ?? "")
        _imapPort = State(initialValue: existingAccount.map { String($0.imapPort) } ?? serverSettings?.imapPort ?? "993")
        _imapSecurity = State(initialValue: existingAccount?.imapSecurity ?? serverSettings?.imapSecurity ?? .ssl)
        _smtpHost = State(initialValue: existingAccount?.smtpHost ?? serverSettings?.smtpHost ?? "")
        _smtpPort = State(initialValue: existingAccount.map { String($0.smtpPort) } ?? serverSettings?.smtpPort ?? "465")
        _smtpSecurity = State(initialValue: existingAccount?.smtpSecurity ?? serverSettings?.smtpSecurity ?? .ssl)
        _password = State(initialValue: "")
        _caldavURL = State(initialValue: existingAccount?.caldavURL?.absoluteString ?? davSettings?.caldavURL ?? "")
        _carddavURL = State(initialValue: existingAccount?.carddavURL?.absoluteString ?? davSettings?.carddavURL ?? "")
        _accountLabel = State(initialValue: existingAccount?.label ?? "")
        _oauthTokens = State(initialValue: nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            navigationButtons
        }
        .frame(width: 520, height: 540)
        .task(id: mode.existingAccount?.id) {
            await preloadStoredCredentialsIfNeeded()
        }
    }

    private var stepIndicator: some View {
        HStack {
            ForEach(Array(visibleSteps.enumerated()), id: \.offset) { index, displayedStep in
                if index > 0 {
                    Rectangle()
                        .fill(hasReached(displayedStep) ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                }
                Circle()
                    .fill(hasReached(displayedStep) ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
        .padding()
    }

    private var visibleSteps: [SetupStep] {
        mode.isEditing ? [.provider, .credentials, .connectionTest, .done] : SetupStep.allCases
    }

    private func hasReached(_ displayedStep: SetupStep) -> Bool {
        displayedStep.rawValue <= step.rawValue
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .provider:
            ProviderSelectionView(
                title: mode.isEditing ? "Edit Account" : "Add Account",
                provider: $provider
            )
        case .credentials:
            CredentialsFormView(
                provider: provider,
                isEditing: mode.isEditing,
                emailAddress: $emailAddress,
                displayName: $displayName,
                imapHost: $imapHost,
                imapPort: $imapPort,
                imapSecurity: $imapSecurity,
                smtpHost: $smtpHost,
                smtpPort: $smtpPort,
                smtpSecurity: $smtpSecurity,
                password: $password,
                caldavURL: $caldavURL,
                carddavURL: $carddavURL,
                davValidationError: davURLValidationError,
                oauthInProgress: $oauthInProgress,
                onTokensObtained: { tokens in
                    oauthTokens = tokens
                }
            )
            .environment(appState)
        case .connectionTest:
            VStack(spacing: 0) {
                ConnectionTestView(
                    results: $testResults,
                    inProgress: $testInProgress,
                    account: buildAccount(),
                    authMaterial: connectionTestAuthMaterial
                )
                .environment(appState)

                if let saveError, mode.isEditing {
                    Text("Failed to update account: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding([.horizontal, .bottom])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .label:
            LabelEntryView(
                accountLabel: $accountLabel,
                emailAddress: emailAddress,
                saveError: saveError,
                saveInProgress: saveInProgress
            )
        case .done:
            DoneView(
                accountLabel: accountLabel,
                emailAddress: emailAddress,
                isEditing: mode.isEditing
            )
        }
    }

    private var navigationButtons: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .disabled(saveInProgress)
            Spacer()
            if step.rawValue > 0 && step != .done {
                Button("Back") {
                    step = SetupStep(rawValue: step.rawValue - 1)!
                }
                .disabled(testInProgress || saveInProgress)
            }
            if step != .done {
                Button(nextButtonTitle) { advanceStep() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
            } else {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    // MARK: - Navigation Logic

    private var nextButtonTitle: String {
        switch step {
        case .provider: return "Next"
        case .credentials: return "Test Connection"
        case .connectionTest:
            if testsPassed {
                return mode.isEditing ? (saveInProgress ? "Updating..." : "Update Account") : "Next"
            }
            return "Retry"
        case .label: return saveInProgress ? "Adding..." : "Add Account"
        case .done: return "Done"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .provider: return true
        case .credentials:
            if provider.usesOAuth {
                return !emailAddress.isEmpty
                    && !oauthInProgress
                    && oauthCredentialsReady
                    && davURLValidationError == nil
            }
            return !emailAddress.isEmpty
                && passwordCredentialsReady
                && !imapHost.isEmpty
                && !smtpHost.isEmpty
                && davURLValidationError == nil
        case .connectionTest: return !testInProgress && !saveInProgress
        case .label: return !accountLabel.isEmpty && !saveInProgress
        case .done: return true
        }
    }

    private var testsPassed: Bool {
        !testResults.isEmpty && testResults.allSatisfy(\.passed)
    }

    private var connectionTestAuthMaterial: ConnectionTestAuthMaterial {
        if let oauthTokens {
            return .oauth2(oauthTokens)
        }
        if let existingAccount = mode.existingAccount,
           let provider = provider.oauthProvider,
           matchesExistingOAuthAuth(existingAccount, provider: provider),
           let storedOAuthTokens {
            return .oauth2(storedOAuthTokens)
        }
        if let existingAccount = mode.existingAccount,
           matchesExistingPasswordAuth(existingAccount),
           password.isEmpty,
           let storedPassword {
            return .password(storedPassword)
        }
        return .password(password)
    }

    private var oauthCredentialsReady: Bool {
        if oauthTokens != nil {
            return true
        }

        guard mode.isEditing,
              let existingAccount = mode.existingAccount,
              case .oauth2(let existingProvider) = existingAccount.authMethod else {
            return false
        }

        return provider.oauthProvider == existingProvider
    }

    private var passwordCredentialsReady: Bool {
        if !password.isEmpty {
            return true
        }

        guard let existingAccount = mode.existingAccount,
              matchesExistingPasswordAuth(existingAccount) else {
            return false
        }

        return storedPassword != nil
    }

    private func advanceStep() {
        switch step {
        case .label:
            saveAccount()
        case .connectionTest where testsPassed && mode.isEditing:
            saveAccount()
        case .connectionTest where !testsPassed:
            // Clear results to trigger .task(id:) in ConnectionTestView.
            // Don't set testInProgress here — runTests() handles that.
            testInProgress = false
            testResults = []
        case .credentials:
            testInProgress = false
            testResults = []
            step = .connectionTest
        case .provider:
            applyProviderDefaults()
            step = .credentials
        default:
            step = SetupStep(rawValue: step.rawValue + 1)!
        }
    }

    private func buildAccount() -> Account {
        let existingAccount = mode.existingAccount
        return Account(
            id: existingAccount?.id ?? UUID(),
            label: mode.isEditing ? (existingAccount?.label ?? accountLabel) : (accountLabel.isEmpty ? "setup" : accountLabel),
            emailAddress: emailAddress,
            displayName: displayName,
            authMethod: provider.authMethod,
            imapHost: imapHost,
            imapPort: Int(imapPort) ?? 993,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 465,
            smtpSecurity: smtpSecurity,
            caldavURL: validatedDAVURL(caldavURL, serviceName: "CalDAV"),
            carddavURL: validatedDAVURL(carddavURL, serviceName: "CardDAV"),
            isEnabled: existingAccount?.isEnabled ?? true,
            lastSyncDate: existingAccount?.lastSyncDate,
            connectionStatus: existingAccount?.connectionStatus ?? .disconnected
        )
    }

    private func saveAccount() {
        let account = buildAccountForSave()

        saveInProgress = true
        saveError = nil
        var pendingAccount = account
        pendingAccount.connectionStatus = .connecting
        appState.upsertPendingAccount(pendingAccount)

        Task {
            do {
                try await persistCredentials(for: account)
                if let existingAccount = mode.existingAccount {
                    try await appState.orchestrator?.updateAccount(label: existingAccount.label, with: account)
                } else {
                    try await appState.orchestrator?.addAccount(account)
                }
                await appState.refreshAccounts()
                await MainActor.run {
                    saveInProgress = false
                    step = .done
                }
            } catch {
                await MainActor.run {
                    if let existingAccount = mode.existingAccount {
                        appState.upsertPendingAccount(existingAccount)
                    } else {
                        appState.removeAccount(id: account.id)
                    }
                    saveInProgress = false
                    saveError = String(describing: error)
                    step = mode.isEditing ? .connectionTest : .label
                }
                if mode.existingAccount == nil {
                    try? await KeychainManager().deleteAll(accountId: account.id)
                }
            }
        }
    }

    private func buildAccountForSave() -> Account {
        let existingAccount = mode.existingAccount
        return Account(
            id: existingAccount?.id ?? UUID(),
            label: mode.isEditing ? (existingAccount?.label ?? accountLabel) : accountLabel,
            emailAddress: emailAddress,
            displayName: displayName,
            authMethod: provider.authMethod,
            imapHost: imapHost,
            imapPort: Int(imapPort) ?? 993,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 465,
            smtpSecurity: smtpSecurity,
            caldavURL: validatedDAVURL(caldavURL, serviceName: "CalDAV"),
            carddavURL: validatedDAVURL(carddavURL, serviceName: "CardDAV"),
            isEnabled: existingAccount?.isEnabled ?? true,
            lastSyncDate: existingAccount?.lastSyncDate,
            connectionStatus: existingAccount?.connectionStatus ?? .disconnected
        )
    }

    private func persistCredentials(for account: Account) async throws {
        let keychainManager = KeychainManager()
        let existingAccount = mode.existingAccount

        switch provider.authMethod {
        case .password:
            if !password.isEmpty {
                try await keychainManager.savePassword(accountId: account.id, password: password)
            } else if existingAccount == nil || !matchesExistingPasswordAuth(existingAccount) {
                throw ClawMailError.authFailed("Enter the password for this account before saving changes.")
            }

            if let existingAccount, case .oauth2 = existingAccount.authMethod {
                try? await keychainManager.deleteOAuthTokens(accountId: account.id)
            }

        case .oauth2(let oauthProvider):
            if let oauthTokens {
                try await keychainManager.saveOAuthTokens(
                    accountId: account.id,
                    accessToken: oauthTokens.accessToken,
                    refreshToken: oauthTokens.refreshToken,
                    expiresAt: oauthTokens.expiresAt
                )
            } else if !matchesExistingOAuthAuth(existingAccount, provider: oauthProvider) {
                throw ClawMailError.authFailed("Complete the browser sign-in before saving changes.")
            }

            if let existingAccount, case .password = existingAccount.authMethod {
                try? await keychainManager.deletePassword(accountId: account.id)
            }
        }
    }

    private func matchesExistingPasswordAuth(_ existingAccount: Account?) -> Bool {
        guard let existingAccount else { return false }
        if case .password = existingAccount.authMethod {
            return true
        }
        return false
    }

    private func matchesExistingOAuthAuth(_ existingAccount: Account?, provider: OAuthProvider) -> Bool {
        guard let existingAccount,
              case .oauth2(let existingProvider) = existingAccount.authMethod else {
            return false
        }
        return existingProvider == provider
    }

    private func preloadStoredCredentialsIfNeeded() async {
        guard let existingAccount = mode.existingAccount else { return }

        let keychainManager = KeychainManager()
        switch existingAccount.authMethod {
        case .password:
            let password = await keychainManager.getPassword(accountId: existingAccount.id)
            await MainActor.run {
                storedPassword = password
                storedOAuthTokens = nil
            }
        case .oauth2:
            let tokens = await keychainManager.getOAuthTokens(accountId: existingAccount.id)
            await MainActor.run {
                storedOAuthTokens = tokens
                storedPassword = nil
            }
        }
    }

    private var davURLValidationError: String? {
        validationError(for: caldavURL, serviceName: "CalDAV")
            ?? validationError(for: carddavURL, serviceName: "CardDAV")
    }

    private func applyProviderDefaults() {
        if let serverSettings = provider.serverSettings {
            imapHost = serverSettings.imapHost
            imapPort = serverSettings.imapPort
            imapSecurity = serverSettings.imapSecurity
            smtpHost = serverSettings.smtpHost
            smtpPort = serverSettings.smtpPort
            smtpSecurity = serverSettings.smtpSecurity
        }

        if let davSettings = provider.davSettings {
            caldavURL = davSettings.caldavURL
            carddavURL = davSettings.carddavURL
        } else {
            caldavURL = ""
            carddavURL = ""
        }
    }

    private func validatedDAVURL(_ rawValue: String, serviceName: String) -> URL? {
        try? DAVURLValidator.validateOptionalURLString(rawValue, serviceName: serviceName)
    }

    private func validationError(for rawValue: String, serviceName: String) -> String? {
        do {
            _ = try DAVURLValidator.validateOptionalURLString(rawValue, serviceName: serviceName)
            return nil
        } catch let error as ClawMailError {
            return error.message
        } catch {
            return String(describing: error)
        }
    }
}

// MARK: - Provider Selection (Extracted Sub-view)

private struct ProviderSelectionView: View {
    let title: String
    @Binding var provider: ProviderChoice

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(title)
                    .font(.title2.bold())
                Text("Choose your account provider:")
                    .foregroundStyle(.secondary)

                ForEach(ProviderChoice.allCases, id: \.rawValue) { choice in
                    providerRow(choice)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func providerRow(_ choice: ProviderChoice) -> some View {
        Button(action: { provider = choice }) {
            HStack {
                Image(systemName: choice.icon)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.rawValue)
                    Text(choice.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if provider == choice {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .background(provider == choice ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(provider == choice ? Color.accentColor : Color.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Credentials Form (Extracted Sub-view)

private struct CredentialsFormView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAdvancedDAV = false
    let provider: ProviderChoice
    let isEditing: Bool
    @Binding var emailAddress: String
    @Binding var displayName: String
    @Binding var imapHost: String
    @Binding var imapPort: String
    @Binding var imapSecurity: ConnectionSecurity
    @Binding var smtpHost: String
    @Binding var smtpPort: String
    @Binding var smtpSecurity: ConnectionSecurity
    @Binding var password: String
    @Binding var caldavURL: String
    @Binding var carddavURL: String
    let davValidationError: String?
    @Binding var oauthInProgress: Bool
    var onTokensObtained: ((OAuthTokens) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                emailSection

                if provider.usesOAuth {
                    Divider()
                    OAuthFlowView(
                        provider: provider.oauthProvider ?? .google,
                        inProgress: $oauthInProgress,
                        onTokensObtained: onTokensObtained
                    )
                    .environment(appState)
                    Divider()
                    optionalSection
                } else {
                    Divider()
                    imapSection
                    smtpSection
                    Divider()
                    optionalSection
                }
            }
            .padding()
        }
    }

    private var emailSection: some View {
        Group {
            Text("Email Settings").font(.headline)
            TextField("Email Address", text: $emailAddress)
                .textFieldStyle(.roundedBorder)
            TextField("Display Name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            if !provider.usesOAuth {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                if isEditing {
                    Text("Leave the password blank to keep the current saved password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if provider == .apple {
                    Text("Use an app-specific password for iCloud Mail when connecting a third-party app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Create an app-specific password", destination: URL(string: "https://support.apple.com/121539")!)
                        .font(.caption)
                }
            } else if isEditing {
                Text("Your existing browser sign-in will stay in place unless you complete browser sign-in again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var imapSection: some View {
        Group {
            Text("IMAP (Incoming)").font(.headline)
            HStack {
                TextField("Host", text: $imapHost)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $imapPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Picker("", selection: $imapSecurity) {
                    Text("SSL").tag(ConnectionSecurity.ssl)
                    Text("STARTTLS").tag(ConnectionSecurity.starttls)
                }
                .frame(width: 100)
                .onChange(of: imapSecurity) { _, newValue in
                    imapPort = newValue == .ssl ? "993" : "143"
                }
            }
        }
    }

    private var smtpSection: some View {
        Group {
            Text("SMTP (Outgoing)").font(.headline)
            HStack {
                TextField("Host", text: $smtpHost)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $smtpPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Picker("", selection: $smtpSecurity) {
                    Text("SSL").tag(ConnectionSecurity.ssl)
                    Text("STARTTLS").tag(ConnectionSecurity.starttls)
                }
                .frame(width: 100)
                .onChange(of: smtpSecurity) { _, newValue in
                    smtpPort = newValue == .ssl ? "465" : "587"
                }
            }
        }
    }

    private var optionalSection: some View {
        Group {
            if provider == .apple {
                Text("iCloud Services").font(.headline).foregroundStyle(.secondary)
                Text("Calendar, Contacts, and Reminders are preconfigured for Apple accounts. Open Advanced only if you need to override the default iCloud service URLs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Advanced Service URLs", isExpanded: $showingAdvancedDAV) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("CalDAV URL", text: $caldavURL)
                            .textFieldStyle(.roundedBorder)
                        TextField("CardDAV URL", text: $carddavURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 6)
                }
            } else {
                Text("Optional Services").font(.headline).foregroundStyle(.secondary)
                TextField("CalDAV URL (optional)", text: $caldavURL)
                    .textFieldStyle(.roundedBorder)
                TextField("CardDAV URL (optional)", text: $carddavURL)
                    .textFieldStyle(.roundedBorder)
            }
            if let davValidationError {
                Text(davValidationError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Label Entry (Extracted Sub-view)

private struct LabelEntryView: View {
    @Binding var accountLabel: String
    let emailAddress: String
    var saveError: String?
    var saveInProgress: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Name Your Account")
                .font(.title2.bold())
            Text("Choose a short label to identify this account:")
                .foregroundStyle(.secondary)
            TextField("Account Label (e.g. Work, Personal)", text: $accountLabel)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .onAppear {
                    if accountLabel.isEmpty, let domain = emailAddress.split(separator: "@").last {
                        accountLabel = String(domain.split(separator: ".").first ?? "account").capitalized
                    }
                }
            if let error = saveError {
                Text("Failed to save account: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .frame(maxWidth: 300)
            }
            if saveInProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving account and connecting...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - Done View (Extracted Sub-view)

private struct DoneView: View {
    let accountLabel: String
    let emailAddress: String
    let isEditing: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(isEditing ? "Account Updated!" : "Account Added!")
                .font(.title2.bold())
            Text("\(accountLabel) (\(emailAddress)) is now configured.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
