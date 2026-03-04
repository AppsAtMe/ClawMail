import SwiftUI
import ClawMailCore

/// Manages the ClawMail daemon lifecycle: orchestrator, IPC server, REST API server.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await startServices()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let state = appState
        let semaphore = DispatchSemaphore(value: 0)
        // Dispatch to a global queue to avoid blocking the main actor,
        // which would deadlock actors that need MainActor isolation.
        DispatchQueue.global().async {
            Task.detached {
                await state.apiServer?.stop()
                await state.ipcServer?.stop()
                await state.orchestrator?.stop()
                semaphore.signal()
            }
        }
        // Wait with timeout to avoid hanging if shutdown stalls (e.g. stuck NIO connections)
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    // MARK: - Service Lifecycle

    private func startServices() async {
        do {
            // Load configuration
            let config = try AppConfig.load()
            appState.config = config
            appState.refreshFromConfig()

            // Initialize database
            let db = try DatabaseManager()

            // Initialize orchestrator
            let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)
            appState.orchestrator = orchestrator

            // Start orchestrator (connects accounts, starts sync)
            try await orchestrator.start()

            // Start IPC server (Unix domain socket)
            let ipcServer = IPCServer(orchestrator: orchestrator)
            try await ipcServer.start()
            appState.ipcServer = ipcServer

            // Retrieve API key for REST server
            let keychainManager = KeychainManager()
            var apiKey = await keychainManager.getAPIKey()
            if apiKey == nil {
                apiKey = try await keychainManager.generateAPIKey()
            }

            // Start REST API server
            let apiServer = APIServer(
                orchestrator: orchestrator,
                port: config.restApiPort,
                apiKey: apiKey
            )
            try await apiServer.start()
            appState.apiServer = apiServer

            // Mark running
            appState.isRunning = true
            appState.launchError = nil

            // Refresh account list
            await appState.refreshAccounts()

            // If no accounts, prompt setup
            if appState.accounts.isEmpty {
                appState.showSettings = true
                appState.settingsTab = .accounts
            }

        } catch {
            appState.launchError = error.localizedDescription
            appState.isRunning = false
        }
    }
}
