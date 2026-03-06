import SwiftUI
import ClawMailCore

/// General settings tab: launch at login, sync settings, audit retention.
struct GeneralTab: View {
    @Environment(AppState.self) private var appState

    @State private var launchAtLogin = true
    @State private var syncInterval = "15"
    @State private var initialSyncDays = "30"
    @State private var auditRetentionDays = "90"
    @State private var idleFolders: [String] = ["INBOX"]
    @State private var newIdleFolder = ""
    @State private var showingResetConfirm = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        appState.config.launchAtLogin = newValue
                        try? appState.config.save()
                        if newValue {
                            LaunchAgentManager.install()
                        } else {
                            LaunchAgentManager.uninstall()
                        }
                    }
            }

            Section("Sync") {
                LabeledContent("Sync interval (minutes)") {
                    TextField("Minutes", text: $syncInterval)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: syncInterval) { _, newValue in
                            if let val = Int(newValue), val > 0 {
                                appState.config.syncIntervalMinutes = val
                                try? appState.config.save()
                                applyRuntimeSyncSettings()
                            }
                        }
                }

                LabeledContent("Initial sync period (days)") {
                    TextField("Days", text: $initialSyncDays)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: initialSyncDays) { _, newValue in
                            if let val = Int(newValue), val > 0 {
                                appState.config.initialSyncDays = val
                                try? appState.config.save()
                                applyRuntimeSyncSettings()
                            }
                        }
                }
            }

            Section("IMAP IDLE Folders") {
                ForEach(idleFolders, id: \.self) { folder in
                    HStack {
                        Text(folder)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if folder != "INBOX" {
                            Button(action: {
                                idleFolders.removeAll { $0 == folder }
                                appState.config.idleFolders = idleFolders
                                try? appState.config.save()
                                applyRuntimeSyncSettings()
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    TextField("Add folder", text: $newIdleFolder)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addIdleFolder() }
                    Button("Add") { addIdleFolder() }
                        .disabled(newIdleFolder.isEmpty)
                }
            }

            Section("Data") {
                LabeledContent("Audit log retention (days)") {
                    TextField("Days", text: $auditRetentionDays)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: auditRetentionDays) { _, newValue in
                            if let val = Int(newValue), val > 0 {
                                appState.config.auditRetentionDays = val
                                try? appState.config.save()
                            }
                        }
                }

                LabeledContent("Database") {
                    Text(DatabaseManager.defaultDatabaseURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Config") {
                    Text(AppConfig.defaultConfigURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section {
                Button("Reset All Settings", role: .destructive) {
                    showingResetConfirm = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadFromConfig() }
        .alert("Reset All Settings", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetSettings() }
        } message: {
            Text("This will reset all settings to defaults. Accounts will not be removed.")
        }
    }

    private func loadFromConfig() {
        let config = appState.config
        launchAtLogin = config.launchAtLogin
        syncInterval = String(config.syncIntervalMinutes)
        initialSyncDays = String(config.initialSyncDays)
        auditRetentionDays = String(config.auditRetentionDays)
        idleFolders = config.idleFolders
    }

    private func addIdleFolder() {
        let folder = newIdleFolder.trimmingCharacters(in: .whitespaces)
        guard !folder.isEmpty, !idleFolders.contains(folder) else { return }
        idleFolders.append(folder)
        newIdleFolder = ""
        appState.config.idleFolders = idleFolders
        try? appState.config.save()
        applyRuntimeSyncSettings()
    }

    private func resetSettings() {
        let accounts = appState.config.accounts
        appState.config = AppConfig(accounts: accounts)
        try? appState.config.save()
        if appState.config.launchAtLogin {
            LaunchAgentManager.install()
        } else {
            LaunchAgentManager.uninstall()
        }
        applyRuntimeSyncSettings()
        Task { await appState.orchestrator?.updateGuardrailConfig(appState.config.guardrails) }
        loadFromConfig()
    }

    private func applyRuntimeSyncSettings() {
        let config = appState.config
        Task {
            try? await appState.orchestrator?.updateSyncSettings(
                syncIntervalMinutes: config.syncIntervalMinutes,
                initialSyncDays: config.initialSyncDays,
                idleFolders: config.idleFolders
            )
        }
    }
}
