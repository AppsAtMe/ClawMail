import SwiftUI
import ClawMailCore

/// Shared observable state for the ClawMail UI.
/// Bridges between the actor-isolated AccountOrchestrator and SwiftUI views.
@MainActor
@Observable
final class AppState {

    // MARK: - Service State

    var isRunning = false
    var launchError: String?

    // MARK: - Account State

    var accounts: [Account] = []
    var connectionStatuses: [String: ConnectionStatus] = [:]

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

    // MARK: - Refresh

    func refreshAccounts() async {
        guard let orchestrator = orchestrator else { return }
        accounts = await orchestrator.listAccounts()
    }

    func refreshFromConfig() {
        accounts = config.accounts
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case accounts = "Accounts"
    case guardrails = "Guardrails"
    case api = "API"
    case activityLog = "Activity Log"
    case general = "General"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .accounts: return "person.crop.circle"
        case .guardrails: return "shield.checkered"
        case .api: return "network"
        case .activityLog: return "list.bullet.rectangle"
        case .general: return "gearshape"
        }
    }
}
