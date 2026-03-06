import SwiftUI
import ClawMailCore

/// General settings tab: launch at login, sync settings, audit retention.
struct GeneralTab: View {
    @Environment(AppState.self) private var environmentAppState
    private let appStateOverride: AppState?
    private let saveConfigAction: @MainActor (AppConfig) throws -> Void
    private let installLaunchAgent: () -> Bool
    private let uninstallLaunchAgent: () -> Bool
    internal let inspection = Inspection<Self>()

    @State private var launchAtLogin = true
    @State private var syncInterval = "15"
    @State private var initialSyncDays = "30"
    @State private var auditRetentionDays = "90"
    @State private var idleFolders: [String] = ["INBOX"]
    @State private var newIdleFolder = ""
    @State private var showingResetConfirm = false
    @State private var errorState: UIErrorState?

    init(
        appState: AppState? = nil,
        initialErrorState: UIErrorState? = nil,
        saveConfigAction: @escaping @MainActor (AppConfig) throws -> Void = Self.defaultSaveConfigAction,
        installLaunchAgent: @escaping () -> Bool = { LaunchAgentManager.install() },
        uninstallLaunchAgent: @escaping () -> Bool = LaunchAgentManager.uninstall
    ) {
        self.appStateOverride = appState
        self.saveConfigAction = saveConfigAction
        self.installLaunchAgent = installLaunchAgent
        self.uninstallLaunchAgent = uninstallLaunchAgent
        _errorState = State(initialValue: initialErrorState)
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
            }

            Section("Sync") {
                LabeledContent("Sync interval (minutes)") {
                    TextField("Minutes", text: $syncInterval)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: syncInterval) { _, newValue in
                            if let val = Int(newValue), val > 0 {
                                if !persistConfigChange(
                                    "Saving sync interval",
                                    update: { $0.syncIntervalMinutes = val },
                                    onSuccess: { applyRuntimeSyncSettings() }
                                ) {
                                    loadFromConfig()
                                }
                            }
                        }
                }

                LabeledContent("Initial sync period (days)") {
                    TextField("Days", text: $initialSyncDays)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: initialSyncDays) { _, newValue in
                            if let val = Int(newValue), val > 0 {
                                if !persistConfigChange(
                                    "Saving initial sync period",
                                    update: { $0.initialSyncDays = val },
                                    onSuccess: { applyRuntimeSyncSettings() }
                                ) {
                                    loadFromConfig()
                                }
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
                                if !persistConfigChange(
                                    "Removing IMAP IDLE folder",
                                    update: { $0.idleFolders = idleFolders },
                                    onSuccess: { applyRuntimeSyncSettings() }
                                ) {
                                    loadFromConfig()
                                }
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
                                if !persistConfigChange(
                                    "Saving audit retention",
                                    update: { $0.auditRetentionDays = val }
                                ) {
                                    loadFromConfig()
                                }
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
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
        .alert("Reset All Settings", isPresented: $showingResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetSettings() }
        } message: {
            Text("This will reset all settings to defaults. Accounts will not be removed.")
        }
        .alert("Operation Failed", isPresented: showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorState?.message ?? "Unknown error.")
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
        if !persistConfigChange(
            "Adding IMAP IDLE folder",
            update: { $0.idleFolders = idleFolders },
            onSuccess: {
                newIdleFolder = ""
                applyRuntimeSyncSettings()
            }
        ) {
            loadFromConfig()
        }
    }

    private func resetSettings() {
        let accounts = appState.config.accounts
        let updatedConfig = AppConfig(accounts: accounts)
        do {
            try saveConfigAction(updatedConfig)
            appState.config = updatedConfig
        } catch {
            errorState = UIErrorState(action: "Resetting settings", error: error)
            loadFromConfig()
            return
        }

        if appState.config.launchAtLogin {
            if !installLaunchAgent() {
                errorState = UIErrorState(message: "Settings were reset, but enabling launch at login failed.")
            }
        } else {
            if !uninstallLaunchAgent() {
                errorState = UIErrorState(message: "Settings were reset, but disabling launch at login failed.")
            }
        }
        applyRuntimeSyncSettings()
        Task { await appState.orchestrator?.updateGuardrailConfig(appState.config.guardrails) }
        loadFromConfig()
    }

    private func applyRuntimeSyncSettings() {
        let config = appState.config
        Task {
            do {
                try await appState.orchestrator?.updateSyncSettings(
                    syncIntervalMinutes: config.syncIntervalMinutes,
                    initialSyncDays: config.initialSyncDays,
                    idleFolders: config.idleFolders
                )
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(
                        action: "Updating running sync settings",
                        error: error
                    )
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

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard persistConfigChange(
            "Saving launch-at-login setting",
            update: { $0.launchAtLogin = enabled }
        ) else {
            loadFromConfig()
            return
        }

        let succeeded = enabled ? installLaunchAgent() : uninstallLaunchAgent()
        if !succeeded {
            errorState = UIErrorState(message: "The setting was saved, but updating the macOS LaunchAgent failed.")
        }
    }

    @discardableResult
    private func persistConfigChange(
        _ action: String,
        update: (inout AppConfig) -> Void,
        onSuccess: (() -> Void)? = nil
    ) -> Bool {
        var updatedConfig = appState.config
        update(&updatedConfig)

        do {
            try saveConfigAction(updatedConfig)
            appState.config = updatedConfig
            onSuccess?()
            return true
        } catch {
            errorState = UIErrorState(action: action, error: error)
            return false
        }
    }

    private static func defaultSaveConfigAction(_ config: AppConfig) throws {
        try config.save()
    }
}
