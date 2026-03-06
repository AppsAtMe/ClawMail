import SwiftUI
import ClawMailCore

// MARK: - Setup Step Enum

enum SetupStep: Int, CaseIterable {
    case provider, credentials, connectionTest, label, done
}

enum ProviderChoice: String, CaseIterable {
    case google = "Google"
    case microsoft = "Microsoft"
    case other = "Other (IMAP/SMTP)"

    var icon: String {
        switch self {
        case .google: return "envelope.badge.person.crop"
        case .microsoft: return "envelope.badge.shield.half.filled"
        case .other: return "server.rack"
        }
    }
}

// MARK: - Account Setup View

struct AccountSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step: SetupStep = .provider
    @State private var provider: ProviderChoice = .other
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
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            navigationButtons
        }
        .frame(width: 500, height: 420)
    }

    private var stepIndicator: some View {
        HStack {
            ForEach(SetupStep.allCases, id: \.rawValue) { s in
                if s.rawValue > 0 {
                    Rectangle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                }
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .provider:
            ProviderSelectionView(provider: $provider)
        case .credentials:
            CredentialsFormView(
                provider: provider,
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
            ConnectionTestView(
                results: $testResults,
                inProgress: $testInProgress,
                account: buildAccount(),
                password: password
            )
            .environment(appState)
        case .label:
            LabelEntryView(accountLabel: $accountLabel, emailAddress: emailAddress, saveError: saveError)
        case .done:
            DoneView(accountLabel: accountLabel, emailAddress: emailAddress)
        }
    }

    private var navigationButtons: some View {
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
            if step.rawValue > 0 && step != .done {
                Button("Back") {
                    step = SetupStep(rawValue: step.rawValue - 1)!
                }
                .disabled(testInProgress)
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
        case .connectionTest: return testsPassed ? "Next" : "Retry"
        case .label: return "Add Account"
        case .done: return "Done"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .provider: return true
        case .credentials:
            if provider != .other {
                return !oauthInProgress && oauthTokens != nil && davURLValidationError == nil
            }
            return !emailAddress.isEmpty
                && !password.isEmpty
                && !imapHost.isEmpty
                && !smtpHost.isEmpty
                && davURLValidationError == nil
        case .connectionTest: return !testInProgress
        case .label: return !accountLabel.isEmpty
        case .done: return true
        }
    }

    private var testsPassed: Bool {
        !testResults.isEmpty && testResults.allSatisfy(\.passed)
    }

    private func advanceStep() {
        switch step {
        case .label:
            saveAccount()
            step = .done
        case .connectionTest where !testsPassed:
            // Clear results to trigger .task(id:) in ConnectionTestView.
            // Don't set testInProgress here — runTests() handles that.
            testInProgress = false
            testResults = []
        case .provider:
            // Auto-fill known server settings for OAuth providers
            if provider == .google {
                imapHost = "imap.gmail.com"; imapPort = "993"; imapSecurity = .ssl
                smtpHost = "smtp.gmail.com"; smtpPort = "465"; smtpSecurity = .ssl
            } else if provider == .microsoft {
                imapHost = "outlook.office365.com"; imapPort = "993"; imapSecurity = .ssl
                smtpHost = "smtp.office365.com"; smtpPort = "587"; smtpSecurity = .starttls
            }
            step = .credentials
        default:
            step = SetupStep(rawValue: step.rawValue + 1)!
        }
    }

    private func buildAccount() -> Account {
        Account(
            label: accountLabel.isEmpty ? "setup" : accountLabel,
            emailAddress: emailAddress,
            displayName: displayName,
            authMethod: provider == .other ? .password : .oauth2(provider: provider == .google ? .google : .microsoft),
            imapHost: imapHost,
            imapPort: Int(imapPort) ?? 993,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 465,
            smtpSecurity: smtpSecurity,
            caldavURL: validatedDAVURL(caldavURL, serviceName: "CalDAV"),
            carddavURL: validatedDAVURL(carddavURL, serviceName: "CardDAV")
        )
    }

    private func saveAccount() {
        let account = Account(
            label: accountLabel,
            emailAddress: emailAddress,
            displayName: displayName,
            authMethod: provider == .other ? .password : .oauth2(provider: provider == .google ? .google : .microsoft),
            imapHost: imapHost,
            imapPort: Int(imapPort) ?? 993,
            imapSecurity: imapSecurity,
            smtpHost: smtpHost,
            smtpPort: Int(smtpPort) ?? 465,
            smtpSecurity: smtpSecurity,
            caldavURL: validatedDAVURL(caldavURL, serviceName: "CalDAV"),
            carddavURL: validatedDAVURL(carddavURL, serviceName: "CardDAV")
        )

        Task {
            do {
                let km = KeychainManager()
                if let tokens = oauthTokens {
                    try await km.saveOAuthTokens(
                        accountId: account.id,
                        accessToken: tokens.accessToken,
                        refreshToken: tokens.refreshToken,
                        expiresAt: tokens.expiresAt
                    )
                } else if !password.isEmpty {
                    try await km.savePassword(accountId: account.id, password: password)
                }
                try await appState.orchestrator?.addAccount(account)
                await appState.refreshAccounts()
            } catch {
                saveError = String(describing: error)
                step = .label
            }
        }
    }

    private var davURLValidationError: String? {
        validationError(for: caldavURL, serviceName: "CalDAV")
            ?? validationError(for: carddavURL, serviceName: "CardDAV")
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
    @Binding var provider: ProviderChoice

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Account")
                .font(.title2.bold())
            Text("Choose your email provider:")
                .foregroundStyle(.secondary)

            ForEach(ProviderChoice.allCases, id: \.rawValue) { choice in
                providerRow(choice)
            }
        }
        .padding()
    }

    private func providerRow(_ choice: ProviderChoice) -> some View {
        Button(action: { provider = choice }) {
            HStack {
                Image(systemName: choice.icon)
                    .frame(width: 24)
                Text(choice.rawValue)
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
    let provider: ProviderChoice
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
                if provider != .other {
                    OAuthFlowView(
                        provider: provider == .google ? .google : .microsoft,
                        inProgress: $oauthInProgress,
                        onTokensObtained: onTokensObtained
                    )
                    .environment(appState)
                } else {
                    manualForm
                }
            }
            .padding()
        }
    }

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            emailSection
            Divider()
            imapSection
            smtpSection
            Divider()
            optionalSection
        }
    }

    private var emailSection: some View {
        Group {
            Text("Email Settings").font(.headline)
            TextField("Email Address", text: $emailAddress)
                .textFieldStyle(.roundedBorder)
            TextField("Display Name", text: $displayName)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
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
            Text("Optional Services").font(.headline).foregroundStyle(.secondary)
            TextField("CalDAV URL (optional)", text: $caldavURL)
                .textFieldStyle(.roundedBorder)
            TextField("CardDAV URL (optional)", text: $carddavURL)
                .textFieldStyle(.roundedBorder)
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
        }
        .padding()
    }
}

// MARK: - Done View (Extracted Sub-view)

private struct DoneView: View {
    let accountLabel: String
    let emailAddress: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Account Added!")
                .font(.title2.bold())
            Text("\(accountLabel) (\(emailAddress)) is now configured.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
