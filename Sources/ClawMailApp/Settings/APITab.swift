import SwiftUI
import ClawMailCore

/// API settings tab: REST API port, API key management, MCP config, webhook URL.
struct APITab: View {
    @Environment(AppState.self) private var environmentAppState
    private let appStateOverride: AppState?
    private let generateAPIKeyAction: @Sendable () async throws -> String
    internal let inspection = Inspection<Self>()

    @State private var port: String = "24601"
    @State private var apiKey: String = ""
    @State private var apiKeyVisible = false
    @State private var apiKeyLoaded = false
    @State private var webhookURL: String = ""
    @State private var keyCopied = false
    @State private var mcpConfigCopied = false
    @State private var googleClientId: String = ""
    @State private var googleClientSecret: String = ""
    @State private var microsoftClientId: String = ""
    @State private var microsoftClientSecret: String = ""
    @State private var googleSecretSaved = false
    @State private var microsoftSecretSaved = false
    @State private var presentedGuide: OAuthSetupGuideProvider?
    @State private var errorState: UIErrorState?

    init(
        appState: AppState? = nil,
        initialErrorState: UIErrorState? = nil,
        generateAPIKeyAction: @escaping @Sendable () async throws -> String = Self.defaultGenerateAPIKeyAction
    ) {
        self.appStateOverride = appState
        self.generateAPIKeyAction = generateAPIKeyAction
        _errorState = State(initialValue: initialErrorState)
    }

    var body: some View {
        Form {
            Section("REST API") {
                LabeledContent("Port") {
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: port) { _, newValue in
                            if let portNum = Int(newValue), portNum > 0, portNum <= 65535 {
                                if !persistConfigChange(
                                    "Saving REST API port",
                                    update: { $0.restApiPort = portNum }
                                ) {
                                    loadState()
                                }
                            }
                        }
                }

                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.isRunning ? "Running on 127.0.0.1:\(port)" : "Stopped")
                    }
                }
            }

            Section("API Key") {
                HStack {
                    if apiKeyLoaded, apiKeyVisible {
                        Text(apiKey)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else if apiKeyLoaded {
                        Text(String(repeating: "\u{2022}", count: min(apiKey.count, 32)))
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("Stored in Keychain. Reveal or copy it only when needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        if apiKeyLoaded {
                            apiKeyVisible.toggle()
                        } else {
                            revealAPIKey()
                        }
                    }) {
                        Image(systemName: apiKeyLoaded && apiKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(apiKeyLoaded && apiKeyVisible ? "Hide API key" : "Show API key")
                }

                HStack {
                    Button("Copy API Key") {
                        copyAPIKey()
                    }

                    if keyCopied {
                        Text("Copied!")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    Spacer()

                    Button("Regenerate") {
                        regenerateAPIKey()
                    }
                }
            }

            Section("MCP Server") {
                LabeledContent("Socket") {
                    Text(IPCServer.defaultSocketPath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                Button("Copy MCP Config") {
                    let mcpConfig = """
                    {
                      "mcpServers": {
                        "clawmail": {
                          "command": "/usr/local/bin/clawmail-mcp",
                          "args": []
                        }
                      }
                    }
                    """
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(mcpConfig, forType: .string)
                    mcpConfigCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        mcpConfigCopied = false
                    }
                }

                if mcpConfigCopied {
                    Text("MCP config copied to clipboard!")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            Section("CLI") {
                LabeledContent("Path") {
                    Text("/usr/local/bin/clawmail")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section("Google OAuth") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Browser sign-in for Gmail, Calendar, and Contacts.")
                        .font(.headline)
                    Text("Use a Google Desktop app OAuth client here. ClawMail requests Gmail, Calendar, and Google CardDAV access, so rerun browser sign-in after changing Google scopes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button("Open Setup Guide") {
                            presentedGuide = .google
                        }
                        Link("Open Google Docs", destination: URL(string: "https://developers.google.com/workspace/guides/create-credentials")!)
                    }
                }

                LabeledContent("Client ID") {
                    TextField("Google Desktop app Client ID", text: $googleClientId)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .onChange(of: googleClientId) { _, newValue in
                            if !persistConfigChange(
                                "Saving Google OAuth client ID",
                                update: { $0.oauthGoogleClientId = newValue.isEmpty ? nil : newValue }
                            ) {
                                loadState()
                            }
                        }
                }

                LabeledContent("Client Secret") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Paste only if Google provided one", text: $googleClientSecret)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 280)
                        HStack(spacing: 12) {
                            Button("Save Secret") {
                                persistOAuthClientSecret(.google, secret: googleClientSecret)
                            }
                            .disabled(googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Clear Stored Secret") {
                                clearOAuthClientSecret(.google)
                            }

                            if googleSecretSaved {
                                Text("Saved")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        Text("Google's desktop docs say the secret can be optional, but if ClawMail reports `client_secret is missing`, store it here and sign in again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Microsoft OAuth") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Browser sign-in for Microsoft 365 / Outlook mail.")
                        .font(.headline)
                    Text("Use an App Registration from Microsoft Entra. The redirect URI will be shown during sign-in (dynamic localhost port).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button("Open Setup Guide") {
                            presentedGuide = .microsoft
                        }
                        Link("Open Microsoft Docs", destination: URL(string: "https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration")!)
                    }
                }

                LabeledContent("Application ID") {
                    TextField("Microsoft Application (client) ID", text: $microsoftClientId)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .onChange(of: microsoftClientId) { _, newValue in
                            if !persistConfigChange(
                                "Saving Microsoft OAuth client ID",
                                update: { $0.oauthMicrosoftClientId = newValue.isEmpty ? nil : newValue }
                            ) {
                                loadState()
                            }
                        }
                }

                LabeledContent("Client Secret") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Optional depending on your registration", text: $microsoftClientSecret)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 280)
                        HStack(spacing: 12) {
                            Button("Save Secret") {
                                persistOAuthClientSecret(.microsoft, secret: microsoftClientSecret)
                            }
                            .disabled(microsoftClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Clear Stored Secret") {
                                clearOAuthClientSecret(.microsoft)
                            }

                            if microsoftSecretSaved {
                                Text("Saved")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        Text("Many desktop registrations can work without a secret, so only save one if your Microsoft setup actually issued it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Webhook") {
                TextField("Webhook URL (optional)", text: $webhookURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: webhookURL) { _, newValue in
                        if !persistConfigChange(
                            "Saving webhook URL",
                            update: { $0.webhookURL = newValue.isEmpty ? nil : newValue }
                        ) {
                            loadState()
                        }
                    }
                Text("Sends POST notifications when new email arrives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $presentedGuide) { provider in
            OAuthSetupGuideSheet(provider: provider)
        }
        .onAppear { loadState() }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
        .alert("Operation Failed", isPresented: showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorState?.message ?? "Unknown error.")
        }
    }

    private func loadState() {
        port = String(appState.config.restApiPort)
        webhookURL = appState.config.webhookURL ?? ""
        googleClientId = appState.config.oauthGoogleClientId ?? ""
        microsoftClientId = appState.config.oauthMicrosoftClientId ?? ""
        apiKey = ""
        apiKeyVisible = false
        apiKeyLoaded = false
        googleClientSecret = ""
        microsoftClientSecret = ""
        googleSecretSaved = false
        microsoftSecretSaved = false
    }

    private func regenerateAPIKey() {
        Task {
            do {
                let newKey = try await generateAPIKeyAction()
                await MainActor.run {
                    apiKey = newKey
                    apiKeyLoaded = true
                    apiKeyVisible = true
                }
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Regenerating API key", error: error)
                }
            }
        }
    }

    private func revealAPIKey() {
        Task {
            let key = await KeychainManager().getAPIKey()
            await MainActor.run {
                apiKey = key ?? ""
                apiKeyLoaded = key != nil
                apiKeyVisible = key != nil
            }
        }
    }

    private func copyAPIKey() {
        Task {
            let key: String
            if apiKeyLoaded {
                key = apiKey
            } else {
                key = await KeychainManager().getAPIKey() ?? ""
            }

            await MainActor.run {
                guard !key.isEmpty else { return }
                apiKey = key
                apiKeyLoaded = true
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
                keyCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    keyCopied = false
                }
            }
        }
    }

    private func persistOAuthClientSecret(_ provider: OAuthProvider, secret: String) {
        Task {
            let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSecret.isEmpty else { return }
            let km = KeychainManager()
            do {
                try await km.saveOAuthClientSecret(trimmedSecret, for: provider)
                await MainActor.run {
                    switch provider {
                    case .google:
                        googleClientSecret = ""
                        googleSecretSaved = true
                    case .microsoft:
                        microsoftClientSecret = ""
                        microsoftSecretSaved = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run {
                            switch provider {
                            case .google:
                                googleSecretSaved = false
                            case .microsoft:
                                microsoftSecretSaved = false
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Saving \(provider.displayName) OAuth client secret", error: error)
                }
            }
        }
    }

    private func clearOAuthClientSecret(_ provider: OAuthProvider) {
        Task {
            let km = KeychainManager()
            do {
                try await km.deleteOAuthClientSecret(for: provider)
                await MainActor.run {
                    switch provider {
                    case .google:
                        googleClientSecret = ""
                        googleSecretSaved = false
                    case .microsoft:
                        microsoftClientSecret = ""
                        microsoftSecretSaved = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Clearing \(provider.displayName) OAuth client secret", error: error)
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

    private var appState: AppState {
        appStateOverride ?? environmentAppState
    }

    private static func defaultGenerateAPIKeyAction() async throws -> String {
        try await KeychainManager().generateAPIKey()
    }

    @discardableResult
    private func persistConfigChange(
        _ action: String,
        update: (inout AppConfig) -> Void
    ) -> Bool {
        var updatedConfig = appState.config
        update(&updatedConfig)

        do {
            try updatedConfig.save()
            appState.config = updatedConfig
            return true
        } catch {
            errorState = UIErrorState(action: action, error: error)
            return false
        }
    }
}

private enum OAuthSetupGuideProvider: String, Identifiable {
    case google
    case microsoft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google:
            return "Google OAuth Setup"
        case .microsoft:
            return "Microsoft OAuth Setup"
        }
    }

    var subtitle: String {
        switch self {
        case .google:
            return "Use this guide to create the Google Desktop app client ClawMail expects."
        case .microsoft:
            return "Use this guide to create the Microsoft Entra app registration for desktop sign-in."
        }
    }
}

private struct OAuthSetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    let provider: OAuthSetupGuideProvider

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(provider.subtitle)
                        .foregroundStyle(.secondary)

                    switch provider {
                    case .google:
                        guideStep(
                            1,
                            title: "Create a Desktop app client",
                            body: "Open Google Cloud Console, go to Google Auth platform, then create a Desktop app OAuth client. Paste the resulting Client ID into ClawMail.",
                            links: [
                                ("Google OAuth client instructions", "https://developers.google.com/workspace/guides/create-credentials"),
                            ]
                        )
                        guideStep(
                            2,
                            title: "Set the project audience correctly",
                            body: "If you are testing with a personal Gmail account, make sure the Google Auth platform audience is External. Internal projects only work for users inside that Google Workspace or Cloud Identity organization.",
                            links: [
                                ("OAuth consent screen instructions", "https://developers.google.com/workspace/guides/configure-oauth-consent"),
                            ]
                        )
                        guideStep(
                            3,
                            title: "Add yourself as a test user if needed",
                            body: "If the consent screen is still in Testing, add the exact Google account you plan to use in ClawMail. Otherwise Google can return Error 403: access_denied.",
                            links: []
                        )
                        guideStep(
                            4,
                            title: "Configure Google Data Access scopes",
                            body: "Include the Gmail IMAP/SMTP scope, Calendar scope, and Google CardDAV scope `https://www.googleapis.com/auth/carddav`. If you change Data Access later, you must rerun browser sign-in in ClawMail to get a fresh token.",
                            links: []
                        )
                        guideStep(
                            5,
                            title: "Add the client secret only if Google issued one or ClawMail asks for it",
                            body: "Google's desktop docs describe the client secret as optional, but if ClawMail reports `client_secret is missing`, paste the secret from that same client into the Google OAuth section in Settings.",
                            links: []
                        )
                        guideStep(
                            6,
                            title: "If Google Calendar still 403s, enable CalDAV API",
                            body: "Mail and contacts can work while CalDAV is still blocked. If calendar testing returns HTTP 403, enable `caldav.googleapis.com` in the same Google project and rerun browser sign-in.",
                            links: [
                                ("Open CalDAV API in Google Cloud Console", "https://console.cloud.google.com/apis/library/caldav.googleapis.com"),
                            ]
                        )

                    case .microsoft:
                        guideStep(
                            1,
                            title: "Create an app registration",
                            body: "Open Microsoft Entra admin center, create a new App Registration, and copy the Application (client) ID into ClawMail.",
                            links: [
                                ("Microsoft desktop app registration instructions", "https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration"),
                            ]
                        )
                        guideStep(
                            2,
                            title: "Add the redirect URI (Mobile and desktop platform)",
                            body: "In Authentication → Add a platform, choose Mobile and desktop applications (NOT Mac/iOS). ClawMail uses a dynamic localhost redirect URI (e.g., `http://127.0.0.1:54321/oauth/callback`). When you start browser sign-in, ClawMail will show the exact URI with a copy button.",
                            links: []
                        )
                        guideStep(
                            3,
                            title: "Only save a client secret if your registration issued one",
                            body: "Some desktop registrations work without a secret. If your Microsoft setup provides one or ClawMail asks for it, store it in the Microsoft OAuth section in Settings.",
                            links: []
                        )
                        guideStep(
                            4,
                            title: "Return to ClawMail and rerun browser sign-in",
                            body: "After you save the Application ID and any needed secret, go back to account setup and run browser sign-in again. ClawMail will display the redirect URI to add to your Azure app registration.",
                            links: []
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(provider.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private func guideStep(
        _ number: Int,
        title: String,
        body: String,
        links: [(String, String)]
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .foregroundStyle(.secondary)
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    if let url = URL(string: link.1) {
                        Link(link.0, destination: url)
                    }
                }
            }
        }
    }
}
