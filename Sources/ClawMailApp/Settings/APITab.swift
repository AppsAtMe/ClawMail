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

            Section("OAuth Client IDs") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These values come from OAuth app registrations you create with Google or Microsoft. ClawMail does not generate them for you.")
                    Text("Google: Google Cloud Console -> Google Auth platform -> Clients -> Create Client -> Desktop app. Paste the resulting Client ID here.")
                    Link("Open Google OAuth client instructions", destination: URL(string: "https://developers.google.com/workspace/guides/create-credentials")!)
                    Text("If your Google OAuth consent screen is in Testing, add your Google account as a test user or Google will return Error 403: access_denied.")
                    Link("Open Google OAuth consent screen instructions", destination: URL(string: "https://developers.google.com/workspace/guides/configure-oauth-consent")!)
                    Text("If Google says 'Ineligible accounts not added' for a personal @gmail.com address, check Google Auth platform -> Audience. Internal projects only allow users in that Workspace or Cloud Identity organization; use External for personal Gmail testing.")
                    Text("If Google still refuses to add the address as a test user, try a normal consumer Gmail account first. Some account types can also be restricted by organization policy or Advanced Protection.")
                    Text("Microsoft: Microsoft Entra admin center -> App registrations -> New registration. Paste the Application (client) ID here. For desktop sign-in, add the Mobile and desktop applications platform with `http://localhost`.")
                    Link("Open Microsoft app registration instructions", destination: URL(string: "https://learn.microsoft.com/en-us/entra/identity-platform/scenario-desktop-app-configuration")!)
                    Text("ClawMail requests the Gmail IMAP/SMTP scope `https://mail.google.com/`, which Google treats as a restricted scope for broader distribution.")
                    Text("In Google Cloud Console, Google Auth platform > Data Access should include the Gmail, Calendar, and Google CardDAV scope `https://www.googleapis.com/auth/carddav` ClawMail requests. Google's live CardDAV endpoint advertised that exact scope in its `WWW-Authenticate` challenge.")
                    Text("If you change Google Data Access after a failed sign-in, go back and run browser sign-in again. Retrying the connection test alone reuses the same token and will not pick up new scopes.")
                    Text("Google's installed-app docs describe the client secret as optional, but if ClawMail reports `client_secret is missing`, paste the Google Client Secret from the same OAuth client here or recreate that client as a Desktop app.")
                    Text("If Gmail mail works but Google Calendar still fails with HTTP 403, enable `CalDAV API` (`caldav.googleapis.com`) in that same Cloud project, then sign in again.")
                    Link("Open CalDAV API in Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/library/caldav.googleapis.com")!)
                    Text("If Gmail mail works but Google Contacts still fails with HTTP 403, rerun Google browser sign-in on the latest build so ClawMail can request `https://www.googleapis.com/auth/carddav`. If Google still grants only `https://www.googleapis.com/auth/contacts` and CardDAV fails after that, stop there and capture the exact error text plus the OAuth/CardDAV log lines for debugging.")
                    Text("For Microsoft and some other providers, the client secret may still be optional depending on how the app registration is configured.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                LabeledContent("Google Client ID") {
                    TextField("Google Client ID", text: $googleClientId)
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

                LabeledContent("Google Client Secret") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Enter new secret to replace the stored one", text: $googleClientSecret)
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
                        Text("Stored secrets are not auto-loaded when this screen opens, which avoids extra Keychain prompts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Microsoft Client ID") {
                    TextField("Microsoft Client ID", text: $microsoftClientId)
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

                LabeledContent("Microsoft Client Secret") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("Enter new secret to replace the stored one", text: $microsoftClientSecret)
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
                        Text("Stored secrets are not auto-loaded when this screen opens, which avoids extra Keychain prompts.")
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
