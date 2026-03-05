import SwiftUI
import ClawMailCore

/// API settings tab: REST API port, API key management, MCP config, webhook URL.
struct APITab: View {
    @Environment(AppState.self) private var appState

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

    var body: some View {
        Form {
            Section("REST API") {
                LabeledContent("Port") {
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onChange(of: port) { _, newValue in
                            if let portNum = Int(newValue), portNum > 0, portNum <= 65535 {
                                appState.config.restApiPort = portNum
                                try? appState.config.save()
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
                            appState.config.oauthGoogleClientId = newValue.isEmpty ? nil : newValue
                            try? appState.config.save()
                        }
                }

                LabeledContent("Google Client Secret") {
                    SecureField("Optional", text: $googleClientSecret)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .onChange(of: googleClientSecret) { _, newValue in
                            appState.config.oauthGoogleClientSecret = newValue.isEmpty ? nil : newValue
                            try? appState.config.save()
                        }
                }

                LabeledContent("Microsoft Client ID") {
                    TextField("Microsoft Client ID", text: $microsoftClientId)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .onChange(of: microsoftClientId) { _, newValue in
                            appState.config.oauthMicrosoftClientId = newValue.isEmpty ? nil : newValue
                            try? appState.config.save()
                        }
                }

                LabeledContent("Microsoft Client Secret") {
                    SecureField("Optional", text: $microsoftClientSecret)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)
                        .onChange(of: microsoftClientSecret) { _, newValue in
                            appState.config.oauthMicrosoftClientSecret = newValue.isEmpty ? nil : newValue
                            try? appState.config.save()
                        }
                }
            }

            Section("Webhook") {
                TextField("Webhook URL (optional)", text: $webhookURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: webhookURL) { _, newValue in
                        appState.config.webhookURL = newValue.isEmpty ? nil : newValue
                        try? appState.config.save()
                    }
                Text("Sends POST notifications when new email arrives.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadState() }
    }

    private func loadState() {
        port = String(appState.config.restApiPort)
        webhookURL = appState.config.webhookURL ?? ""
        googleClientId = appState.config.oauthGoogleClientId ?? ""
        googleClientSecret = appState.config.oauthGoogleClientSecret ?? ""
        microsoftClientId = appState.config.oauthMicrosoftClientId ?? ""
        microsoftClientSecret = appState.config.oauthMicrosoftClientSecret ?? ""
        Task {
            let km = KeychainManager()
            if let key = await km.getAPIKey() {
                await MainActor.run { apiKey = key }
            }
        }
    }

    private func regenerateAPIKey() {
        Task {
            let km = KeychainManager()
            if let newKey = try? await km.generateAPIKey() {
                await MainActor.run { apiKey = newKey }
            }
        }
    }
}
