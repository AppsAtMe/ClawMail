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
    @State private var webhookURL: String = ""
    @State private var keyCopied = false
    @State private var mcpConfigCopied = false
    @State private var googleClientId: String = ""
    @State private var googleClientSecret: String = ""
    @State private var microsoftClientId: String = ""
    @State private var microsoftClientSecret: String = ""
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
                    if apiKeyVisible {
                        Text(apiKey)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "\u{2022}", count: min(apiKey.count, 32)))
                            .font(.system(.body, design: .monospaced))
                    }
                    Spacer()
                    Button(action: { apiKeyVisible.toggle() }) {
                        Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(apiKeyVisible ? "Hide API key" : "Show API key")
                }

                HStack {
                    Button("Copy API Key") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(apiKey, forType: .string)
                        keyCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            keyCopied = false
                        }
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
                    SecureField("Paste if Google provided one", text: $googleClientSecret)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .onChange(of: googleClientSecret) { _, newValue in
                            Task {
                                let km = KeychainManager()
                                do {
                                    if newValue.isEmpty {
                                        try await km.deleteOAuthClientSecret(for: .google)
                                    } else {
                                        try await km.saveOAuthClientSecret(newValue, for: .google)
                                    }
                                } catch {
                                    await MainActor.run {
                                        errorState = UIErrorState(action: "Saving Google OAuth client secret", error: error)
                                        loadState()
                                    }
                                }
                            }
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
                    SecureField("Optional", text: $microsoftClientSecret)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .onChange(of: microsoftClientSecret) { _, newValue in
                            Task {
                                let km = KeychainManager()
                                do {
                                    if newValue.isEmpty {
                                        try await km.deleteOAuthClientSecret(for: .microsoft)
                                    } else {
                                        try await km.saveOAuthClientSecret(newValue, for: .microsoft)
                                    }
                                } catch {
                                    await MainActor.run {
                                        errorState = UIErrorState(action: "Saving Microsoft OAuth client secret", error: error)
                                        loadState()
                                    }
                                }
                            }
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
        Task {
            let km = KeychainManager()
            async let apiKeyResult = km.getAPIKey()
            async let googleResult = km.getOAuthClientSecret(for: .google)
            async let microsoftResult = km.getOAuthClientSecret(for: .microsoft)
            let (apiKeyVal, googleVal, microsoftVal) = await (apiKeyResult, googleResult, microsoftResult)
            await MainActor.run {
                if let key = apiKeyVal { apiKey = key }
                googleClientSecret = googleVal ?? ""
                microsoftClientSecret = microsoftVal ?? ""
            }
        }
    }

    private func regenerateAPIKey() {
        Task {
            do {
                let newKey = try await generateAPIKeyAction()
                await MainActor.run { apiKey = newKey }
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Regenerating API key", error: error)
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
