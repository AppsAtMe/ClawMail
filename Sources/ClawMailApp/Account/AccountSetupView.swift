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
    case fastmail = "Fastmail"
    case other = "Other Mail Account"

    static let defaultChoice: ProviderChoice = .apple

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "envelope.badge.person.crop"
        case .microsoft: return "envelope.badge.shield.half.filled"
        case .fastmail: return "paperplane.circle"
        case .other: return "server.rack"
        }
    }

    var subtitle: String {
        switch self {
        case .apple:
            return "iCloud Mail, Calendar, Contacts, and Reminders with Apple's app-password setup"
        case .google:
            return "Browser sign-in with Gmail, Calendar, and Contacts"
        case .microsoft:
            return "Browser sign-in with Microsoft mail; DAV support varies"
        case .fastmail:
            return "App-password setup with Fastmail mail, calendar, and contacts defaults"
        case .other:
            return "Manual IMAP, SMTP, and optional DAV configuration"
        }
    }

    var oauthProvider: OAuthProvider? {
        switch self {
        case .google: return .google
        case .microsoft: return .microsoft
        case .apple, .fastmail, .other: return nil
        }
    }

    var usesOAuth: Bool {
        oauthProvider != nil
    }

    var allowsManualEmailEntryDuringSetup: Bool {
        switch self {
        case .google, .microsoft:
            // Email is auto-populated from OAuth identity token
            return false
        case .apple, .fastmail, .other:
            return true
        }
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
        case .fastmail:
            return ProviderServerSettings(
                imapHost: "imap.fastmail.com",
                imapPort: "993",
                imapSecurity: .ssl,
                smtpHost: "smtp.fastmail.com",
                smtpPort: "465",
                smtpSecurity: .ssl
            )
        case .other:
            return nil
        }
    }

    func defaultDAVSettings(emailAddress: String) -> ProviderDAVSettings? {
        switch self {
        case .apple:
            return ProviderDAVSettings(
                caldavURL: "https://caldav.icloud.com",
                carddavURL: "https://contacts.icloud.com"
            )
        case .google:
            return ProviderDAVSettings(
                caldavURL: Self.googleCalDAVURL(emailAddress: emailAddress),
                carddavURL: "https://www.googleapis.com/.well-known/carddav"
            )
        case .fastmail:
            return ProviderDAVSettings(
                caldavURL: "https://caldav.fastmail.com/dav/calendars/user/",
                carddavURL: "https://carddav.fastmail.com/dav/addressbooks/user/"
            )
        case .microsoft, .other:
            return nil
        }
    }

    var hasPresetDAVServices: Bool {
        switch self {
        case .apple, .google, .fastmail:
            return true
        case .microsoft, .other:
            return false
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
            if account.imapHost.caseInsensitiveCompare("imap.fastmail.com") == .orderedSame,
               account.smtpHost.caseInsensitiveCompare("smtp.fastmail.com") == .orderedSame {
                return .fastmail
            }
            return .other
        }
    }

    private static func googleCalDAVURL(emailAddress: String) -> String? {
        let trimmedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return nil }
        return "https://apidata.googleusercontent.com/caldav/v2/\(trimmedEmail)/user"
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
    let caldavURL: String?
    let carddavURL: String?
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

enum AccountSetupCredentialStatus: Equatable {
    case loadingSavedPassword
    case savedPasswordReady
    case missingSavedPassword
    case newPasswordWillReplace
    case loadingSavedOAuth
    case savedOAuthReady
    case missingSavedOAuth
    case newOAuthReady
    case passwordRequired
    case browserSignInRequired

    var icon: String {
        switch self {
        case .loadingSavedPassword, .loadingSavedOAuth:
            return "hourglass"
        case .savedPasswordReady, .savedOAuthReady, .newPasswordWillReplace, .newOAuthReady:
            return "checkmark.circle.fill"
        case .missingSavedPassword, .missingSavedOAuth, .passwordRequired, .browserSignInRequired:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .loadingSavedPassword, .loadingSavedOAuth:
            return .orange
        case .savedPasswordReady, .savedOAuthReady, .newPasswordWillReplace, .newOAuthReady:
            return .green
        case .missingSavedPassword, .missingSavedOAuth, .passwordRequired, .browserSignInRequired:
            return .red
        }
    }

    var message: String {
        switch self {
        case .loadingSavedPassword:
            return "Loading the saved password for this account."
        case .savedPasswordReady:
            return "Saved password ready. Leave the password blank to keep using it for connection tests and the update."
        case .missingSavedPassword:
            return "No saved password was available. Enter a password before you test and update this account."
        case .newPasswordWillReplace:
            return "A new password is ready and will replace the current saved password when you update the account."
        case .loadingSavedOAuth:
            return "Loading the saved browser sign-in for this account."
        case .savedOAuthReady:
            return "Saved browser sign-in ready. You can retest and update without signing in again."
        case .missingSavedOAuth:
            return "No saved browser sign-in was available. Complete browser sign-in again before you test and update this account."
        case .newOAuthReady:
            return "A fresh browser sign-in is ready and will replace the current saved sign-in when you update the account."
        case .passwordRequired:
            return "Enter a password for this provider before you test and update the account."
        case .browserSignInRequired:
            return "Complete browser sign-in for this provider before you test and update the account."
        }
    }
}

struct AccountSetupCredentialState {
    let existingAccount: Account?
    let provider: ProviderChoice
    let enteredPassword: String
    let enteredOAuthTokens: OAuthTokens?
    let storedPassword: String?
    let storedOAuthTokens: OAuthTokens?
    let storedCredentialsDidLoad: Bool

    var passwordCredentialsReady: Bool {
        if !enteredPassword.isEmpty {
            return true
        }

        guard existingPasswordAuthMatches else { return false }
        return storedCredentialsDidLoad && storedPassword != nil
    }

    var oauthCredentialsReady: Bool {
        if enteredOAuthTokens != nil {
            return true
        }

        guard existingOAuthAuthMatches else { return false }
        return storedCredentialsDidLoad && storedOAuthTokens != nil
    }

    var connectionTestAuthMaterial: ConnectionTestAuthMaterial {
        if let activeOAuthTokens {
            return .oauth2(activeOAuthTokens)
        }

        if !enteredPassword.isEmpty {
            return .password(enteredPassword)
        }

        if existingPasswordAuthMatches, let storedPassword {
            return .password(storedPassword)
        }

        return .password(enteredPassword)
    }

    var activeOAuthTokens: OAuthTokens? {
        if let enteredOAuthTokens {
            return enteredOAuthTokens
        }

        if existingOAuthAuthMatches, let storedOAuthTokens {
            return storedOAuthTokens
        }

        return nil
    }

    var authorizedOAuthEmail: String? {
        activeOAuthTokens?.authorizedEmail
    }

    var editCredentialStatus: AccountSetupCredentialStatus? {
        guard existingAccount != nil else { return nil }

        if provider.usesOAuth {
            if enteredOAuthTokens != nil {
                return .newOAuthReady
            }
            if existingOAuthAuthMatches {
                guard storedCredentialsDidLoad else { return .loadingSavedOAuth }
                return storedOAuthTokens == nil ? .missingSavedOAuth : .savedOAuthReady
            }
            return .browserSignInRequired
        }

        if !enteredPassword.isEmpty {
            return .newPasswordWillReplace
        }
        if existingPasswordAuthMatches {
            guard storedCredentialsDidLoad else { return .loadingSavedPassword }
            return storedPassword == nil ? .missingSavedPassword : .savedPasswordReady
        }
        return .passwordRequired
    }

    private var existingPasswordAuthMatches: Bool {
        guard !provider.usesOAuth, let existingAccount else { return false }
        if case .password = existingAccount.authMethod {
            return true
        }
        return false
    }

    private var existingOAuthAuthMatches: Bool {
        guard let existingAccount,
              let provider = provider.oauthProvider,
              case .oauth2(let existingProvider) = existingAccount.authMethod else {
            return false
        }
        return existingProvider == provider
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
    @State private var storedCredentialsDidLoad = false
    @State private var saveError: String?
    @State private var saveInProgress = false

    init(mode: AccountSetupMode = .add) {
        self.mode = mode

        let existingAccount = mode.existingAccount
        let inferredProvider = existingAccount.map(ProviderChoice.inferred(from:)) ?? ProviderChoice.defaultChoice
        let serverSettings = inferredProvider.serverSettings
        let davSettings = inferredProvider.defaultDAVSettings(emailAddress: existingAccount?.emailAddress ?? "")

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
        .onChange(of: emailAddress) { oldValue, newValue in
            syncDerivedDAVDefaults(oldEmailAddress: oldValue, newEmailAddress: newValue)
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
                mode: mode,
                provider: provider,
                credentialStatus: credentialState.editCredentialStatus,
                emailAddress: $emailAddress,
                authorizedOAuthEmail: credentialState.authorizedOAuthEmail,
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
                    applyOAuthTokens(tokens)
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
                displayName: displayName,
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
                Button(backButtonTitle) {
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

    private var backButtonTitle: String {
        if mode.isEditing && step == .credentials {
            return "Change Provider"
        }
        return "Back"
    }

    private var nextButtonTitle: String {
        switch step {
        case .provider: return "Next"
        case .credentials: return "Test Connection"
        case .connectionTest:
            if testsPassed {
                return mode.isEditing ? (saveInProgress ? "Updating..." : "Update Account") : "Next"
            }
            return "Retry Test"
        case .label: return saveInProgress ? "Adding..." : "Add Account"
        case .done: return "Done"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .provider: return true
        case .credentials:
            if provider.usesOAuth {
                return oauthEmailReady
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
        credentialState.connectionTestAuthMaterial
    }

    private var configuredEmailAddress: String {
        if provider.usesOAuth, let authorizedOAuthEmail = credentialState.authorizedOAuthEmail {
            return authorizedOAuthEmail
        }
        return emailAddress
    }

    private var credentialState: AccountSetupCredentialState {
        AccountSetupCredentialState(
            existingAccount: mode.existingAccount,
            provider: provider,
            enteredPassword: password,
            enteredOAuthTokens: oauthTokens,
            storedPassword: storedPassword,
            storedOAuthTokens: storedOAuthTokens,
            storedCredentialsDidLoad: storedCredentialsDidLoad
        )
    }

    private var oauthCredentialsReady: Bool {
        credentialState.oauthCredentialsReady
    }

    private var oauthEmailReady: Bool {
        if provider.allowsManualEmailEntryDuringSetup {
            return !emailAddress.isEmpty
        }
        return !configuredEmailAddress.isEmpty
    }

    private var passwordCredentialsReady: Bool {
        credentialState.passwordCredentialsReady
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
            emailAddress: configuredEmailAddress,
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
        let initialCredentials = connectionTestAuthMaterial.credentials()

        saveInProgress = true
        saveError = nil
        var pendingAccount = account
        pendingAccount.connectionStatus = .connecting
        appState.upsertPendingAccount(pendingAccount)

        Task {
            do {
                try await persistCredentials(for: account)
                if let existingAccount = mode.existingAccount {
                    try await appState.orchestrator?.updateAccount(
                        label: existingAccount.label,
                        with: account,
                        initialCredentials: initialCredentials
                    )
                } else {
                    try await appState.orchestrator?.addAccount(account, initialCredentials: initialCredentials)
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
            emailAddress: configuredEmailAddress,
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
                try await keychainManager.saveOAuthTokens(accountId: account.id, tokens: oauthTokens)
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

        await MainActor.run {
            storedCredentialsDidLoad = false
            storedPassword = nil
            storedOAuthTokens = nil
        }

        let keychainManager = KeychainManager()
        switch existingAccount.authMethod {
        case .password:
            let password = await keychainManager.getPassword(accountId: existingAccount.id)
            await MainActor.run {
                storedPassword = password
                storedOAuthTokens = nil
                storedCredentialsDidLoad = true
            }
        case .oauth2:
            let tokens = await keychainManager.getOAuthTokens(accountId: existingAccount.id)
            await MainActor.run {
                storedOAuthTokens = tokens
                storedPassword = nil
                storedCredentialsDidLoad = true
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

        if let davSettings = provider.defaultDAVSettings(emailAddress: emailAddress) {
            caldavURL = davSettings.caldavURL ?? ""
            carddavURL = davSettings.carddavURL ?? ""
        } else {
            caldavURL = ""
            carddavURL = ""
        }
    }

    private func syncDerivedDAVDefaults(oldEmailAddress: String, newEmailAddress: String) {
        let oldDefaults = provider.defaultDAVSettings(emailAddress: oldEmailAddress)
        let newDefaults = provider.defaultDAVSettings(emailAddress: newEmailAddress)
        applyDerivedDAVDefault(&caldavURL, oldDefault: oldDefaults?.caldavURL, newDefault: newDefaults?.caldavURL)
        applyDerivedDAVDefault(&carddavURL, oldDefault: oldDefaults?.carddavURL, newDefault: newDefaults?.carddavURL)
    }

    private func applyOAuthTokens(_ tokens: OAuthTokens) {
        oauthTokens = tokens
        if let authorizedEmail = tokens.authorizedEmail {
            emailAddress = authorizedEmail
        }
    }

    private func applyDerivedDAVDefault(_ value: inout String, oldDefault: String?, newDefault: String?) {
        let normalizedOldDefault = oldDefault ?? ""
        let shouldReplace = value.isEmpty || value == normalizedOldDefault
        guard shouldReplace else { return }
        value = newDefault ?? ""
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(provider == choice ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(provider == choice ? Color.accentColor : Color.secondary.opacity(0.3))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Credentials Form (Extracted Sub-view)

private struct CredentialsFormView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAdvancedDAV = false
    let mode: AccountSetupMode
    let provider: ProviderChoice
    let credentialStatus: AccountSetupCredentialStatus?
    @Binding var emailAddress: String
    let authorizedOAuthEmail: String?
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
                if let existingAccount = mode.existingAccount {
                    existingAccountBanner(existingAccount)
                    Divider()
                }

                emailSection

                if provider.usesOAuth {
                    Divider()
                    OAuthFlowView(
                        provider: provider.oauthProvider ?? .google,
                        loginHint: emailAddress,
                        inProgress: $oauthInProgress,
                        onTokensObtained: onTokensObtained
                    )
                    .environment(appState)
                    Divider()
                    optionalSection
                } else {
                    Divider()
                    if provider == .other {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server Settings")
                                .font(.headline)
                            Text("Enter your email provider's IMAP and SMTP server details. Not sure what to enter?")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("View Account Setup Guide →", destination: URL(string: "https://github.com/AppsAtMe/ClawMail/blob/main/docs/ACCOUNTS.md")!)
                                .font(.caption)
                        }
                    }
                    imapSection
                    smtpSection
                    Divider()
                    optionalSection
                }
            }
            .padding()
        }
    }

    private func existingAccountBanner(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editing \(account.label)")
                        .font(.headline)
                    Text("These fields are prefilled from the current account so you can update it in place instead of starting over.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("Existing Account")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if let credentialStatus {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: credentialStatus.icon)
                        .foregroundStyle(credentialStatus.tint)
                        .padding(.top, 1)
                    Text(credentialStatus.message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(provider.usesOAuth ? "Identity & Sign-In" : "Email Settings").font(.headline)
            if provider.usesOAuth, let authorizedOAuthEmail {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authorized Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text(authorizedOAuthEmail)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.35))
                    )
                }
            } else if provider.usesOAuth, !provider.allowsManualEmailEntryDuringSetup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authorized Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.secondary)
                        Text(emailAddress.isEmpty ? "Added after browser sign-in" : emailAddress)
                            .foregroundStyle(emailAddress.isEmpty ? .secondary : .primary)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                }
            } else {
                TextField("Email Address", text: $emailAddress)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Sender Name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            Text(
                provider.usesOAuth
                ? "This is the name recipients see in outgoing mail. ClawMail asks for a separate local account nickname in the final step."
                : "This is the name recipients see in outgoing mail."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if !provider.usesOAuth {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                if mode.isEditing {
                    Text("Leave the password blank to keep the current saved password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                switch provider {
                case .apple:
                    Text("Use an app-specific password for iCloud Mail when connecting a third-party app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Create an app-specific password", destination: URL(string: "https://support.apple.com/121539")!)
                        .font(.caption)
                case .fastmail:
                    Text("Use a Fastmail app password for third-party mail, calendar, and contacts access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Create a Fastmail app password", destination: URL(string: "https://www.fastmail.help/hc/en-us/articles/360058752854")!)
                        .font(.caption)
                case .google, .microsoft:
                    EmptyView()
                case .other:
                    Text("Enter your email provider's IMAP/SMTP server details. See the Account Setup Guide for help finding these settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Open Account Setup Guide", destination: URL(string: "https://github.com/AppsAtMe/ClawMail/blob/main/docs/ACCOUNTS.md")!)
                        .font(.caption)
                }
            } else if let authorizedOAuthEmail {
                Text("Browser sign-in verified \(authorizedOAuthEmail). ClawMail will use this address for the account. To switch accounts, run browser sign-in again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !provider.allowsManualEmailEntryDuringSetup {
                Text("Click Open Browser below to choose the account. ClawMail fills in the authorized email after browser sign-in completes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if mode.isEditing {
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
            if provider.hasPresetDAVServices {
                presetDAVSection
            } else {
                Text("Optional Services").font(.headline).foregroundStyle(.secondary)
                if provider == .microsoft {
                    Text("Mail is preconfigured for Microsoft accounts. Enter CalDAV or CardDAV URLs only if your tenant or provider publishes them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    @ViewBuilder
    private var presetDAVSection: some View {
        switch provider {
        case .apple:
            Text("iCloud Services").font(.headline).foregroundStyle(.secondary)
            Text("Calendar, Contacts, and Reminders are preconfigured for Apple accounts. Open Advanced only if you need to override the default iCloud service URLs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .google:
            Text("Google Services").font(.headline).foregroundStyle(.secondary)
            Text("Contacts use Google's official CardDAV discovery URL. Calendar uses your primary Google Calendar based on the email address above. Google Tasks is not exposed through CalDAV.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .fastmail:
            Text("Fastmail Services").font(.headline).foregroundStyle(.secondary)
            Text("Mail, calendar, and contacts are preconfigured for Fastmail. Open Advanced only if you need to override the default Fastmail service URLs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .microsoft, .other:
            EmptyView()
        }

        DisclosureGroup("Advanced Service URLs", isExpanded: $showingAdvancedDAV) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("CalDAV URL", text: $caldavURL)
                    .textFieldStyle(.roundedBorder)
                TextField("CardDAV URL", text: $carddavURL)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, 6)
        }
    }
}

// MARK: - Label Entry (Extracted Sub-view)

private struct LabelEntryView: View {
    @Binding var accountLabel: String
    let displayName: String
    let emailAddress: String
    var saveError: String?
    var saveInProgress: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Name This Account in ClawMail")
                .font(.title2.bold())
            Text("Pick a short local nickname like Work or Personal. This is separate from your sender name.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Sender Identity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(senderIdentitySummary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }
            .frame(maxWidth: 300, alignment: .leading)
            TextField("Account Nickname (e.g. Work, Personal)", text: $accountLabel)
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

    private var senderIdentitySummary: String {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDisplayName.isEmpty {
            return trimmedEmail.isEmpty ? "Filled in from the sign-in step." : trimmedEmail
        }
        if trimmedEmail.isEmpty {
            return trimmedDisplayName
        }
        return "\(trimmedDisplayName) <\(trimmedEmail)>"
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
