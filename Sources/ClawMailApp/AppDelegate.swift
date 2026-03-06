import SwiftUI
import UserNotifications
import ClawMailCore
import ClawMailAppLib

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

            // Wire webhook manager (if configured)
            let webhookManager = WebhookManager(urlString: config.webhookURL)
            appState.webhookManager = webhookManager

            // Wire orchestrator notifications → IPC server (MCP push) + webhooks
            let wm = webhookManager
            await orchestrator.setCallbacks(
                onNewMail: { accountLabel, folder in
                    ipcServer.sendNotification(JSONRPCNotification(
                        method: "clawmail/newMail",
                        params: ["account": .string(accountLabel), "folder": .string(folder)]
                    ))
                    if let wm = wm {
                        Task { await wm.notifyNewEmail(account: accountLabel, folder: folder) }
                    }
                },
                onConnectionStatusChanged: { accountLabel, status in
                    ipcServer.sendNotification(JSONRPCNotification(
                        method: "clawmail/connectionStatus",
                        params: [
                            "account": .string(accountLabel),
                            "status": .string(String(describing: status)),
                        ]
                    ))
                },
                onError: { accountLabel, errorMessage in
                    ipcServer.sendNotification(JSONRPCNotification(
                        method: "clawmail/error",
                        params: [
                            "account": .string(accountLabel),
                            "error": .string(errorMessage),
                        ]
                    ))
                }
            )

            // Request notification permission (no-op if already granted)
            await Self.requestNotificationAuthorization()

            // Wire pending approval → macOS notification
            await orchestrator.setPendingApprovalCallback { accountLabel, emails in
                Task {
                    await Self.schedulePendingApprovalNotification(accountLabel: accountLabel, emails: emails)
                }
            }

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
            appState.launchError = String(describing: error)
            appState.isRunning = false
        }
    }

    private static func requestNotificationAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            log("Failed to request notification authorization: \(describe(error))")
        }
    }

    private static func schedulePendingApprovalNotification(accountLabel: String, emails: [String]) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "ClawMail: Recipient Approval Required"
        content.body = "Account \(accountLabel): \(emails.joined(separator: ", ")) need approval before sending."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pending-approval-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            log("Failed to schedule pending approval notification for \(accountLabel): \(describe(error))")
        }
    }

    private static func log(_ message: String) {
        let line = "[ClawMailApp] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func describe(_ error: Error) -> String {
        if let clawMailError = error as? ClawMailError {
            return clawMailError.message
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}
