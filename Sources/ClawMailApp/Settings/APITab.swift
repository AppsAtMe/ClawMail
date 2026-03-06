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
                Text("Register your app at the Google Cloud Console or Azure AD portal, then enter the credentials here.")
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
                    SecureField("Optional", text: $googleClientSecret)
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
