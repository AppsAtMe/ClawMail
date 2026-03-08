import SwiftUI
import ClawMailCore
import ClawMailAppLib

/// Shared observable state for the ClawMail UI.
/// Bridges between the actor-isolated AccountOrchestrator and SwiftUI views.
@MainActor
@Observable
final class AppState {

    // MARK: - Service State

    var isRunning = false
    var launchError: String?
    var isQuitting = false

    // MARK: - Account State

    var accounts: [Account] = []
    var connectionStatuses: [String: ConnectionStatus] = [:]
    var accountActivity: [String: String] = [:]

    // MARK: - Agent State

    var agentConnected = false
    var lastActivity: String?

    // MARK: - Services (non-UI, held for lifecycle)

    var orchestrator: AccountOrchestrator?
    var ipcServer: IPCServer?
    var apiServer: APIServer?
    var webhookManager: WebhookManager?

    // MARK: - Config

    var config: AppConfig = AppConfig()

    // MARK: - Navigation

    var showSettings = false
    var settingsTab: SettingsTab = .accounts
    var showAccountSetup = false
    var selectedSettingsAccountID: UUID?

    // MARK: - Refresh

    func refreshAccounts() async {
        guard let orchestrator = orchestrator else { return }
        applyAccounts(await orchestrator.listAccounts())
    }

    func refreshFromConfig() {
        applyAccounts(config.accounts)
    }

    func upsertPendingAccount(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        connectionStatuses[account.label] = account.connectionStatus
        ensureSelectedSettingsAccount(preferred: account.id)
    }

    func removeAccount(id: UUID) {
        guard let removed = accounts.first(where: { $0.id == id }) else { return }
        accounts.removeAll { $0.id == id }
        connectionStatuses.removeValue(forKey: removed.label)
        accountActivity.removeValue(forKey: removed.label)
        ensureSelectedSettingsAccount()
    }

    func updateConnectionStatus(_ status: ConnectionStatus, for accountLabel: String) {
        connectionStatuses[accountLabel] = status
        guard let index = accounts.firstIndex(where: { $0.label == accountLabel }) else { return }
        accounts[index].connectionStatus = status
    }

    func recordActivity(_ message: String, accountLabel: String? = nil) {
        lastActivity = message
        if let accountLabel {
            accountActivity[accountLabel] = message
        }
    }

    func focusSettingsAccount(_ id: UUID?) {
        settingsTab = .accounts
        ensureSelectedSettingsAccount(preferred: id)
    }

    func ensureSelectedSettingsAccount(preferred preferredID: UUID? = nil) {
        if let preferredID, accounts.contains(where: { $0.id == preferredID }) {
            selectedSettingsAccountID = preferredID
            return
        }

        if let selectedSettingsAccountID, accounts.contains(where: { $0.id == selectedSettingsAccountID }) {
            return
        }

        selectedSettingsAccountID = accounts.first?.id
    }

    private func applyAccounts(_ newAccounts: [Account]) {
        accounts = newAccounts
        connectionStatuses = Dictionary(uniqueKeysWithValues: newAccounts.map { ($0.label, $0.connectionStatus) })
        ensureSelectedSettingsAccount()
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case guardrails = "Guardrails"
    case api = "API"
    case activityLog = "Activity Log"
    case general = "General"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .guardrails: return "shield.checkered"
        case .api: return "network"
        case .activityLog: return "list.bullet.rectangle"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}
