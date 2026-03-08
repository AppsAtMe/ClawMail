import SwiftUI
import UserNotifications
import ClawMailCore
import ClawMailAppLib

private final class IPCServerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: IPCServer?

    var value: IPCServer? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}

/// Manages the ClawMail daemon lifecycle: orchestrator, IPC server, REST API server.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let settingsAutoOpenAttempts = 8
    private static let settingsAutoOpenRetryDelay: Duration = .milliseconds(250)
    private static let forcedTerminationDelay: TimeInterval = 3

    let appState = AppState()
    private let terminationCoordinator = AppTerminationCoordinator()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await startServices()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let apiServer = appState.apiServer
        let ipcServer = appState.ipcServer
        let orchestrator = appState.orchestrator
        let semaphore = DispatchSemaphore(value: 0)

        Self.log(
            "applicationWillTerminate: stopping services " +
            "(api=\(apiServer != nil), ipc=\(ipcServer != nil), orchestrator=\(orchestrator != nil))."
        )

        Task.detached {
            await apiServer?.stop()
            await ipcServer?.stop()
            await orchestrator?.stop()
            semaphore.signal()
        }

        // Wait with timeout to avoid hanging if shutdown stalls (e.g. stuck NIO connections).
        let completedBeforeTimeout = semaphore.wait(timeout: .now() + 2.0) == .success
        if completedBeforeTimeout {
            Self.log("applicationWillTerminate: service shutdown completed before timeout.")
        } else {
            Self.log("applicationWillTerminate: service shutdown timed out after 2.0 seconds.")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alreadyQuitting = appState.isQuitting
        Self.log("applicationShouldTerminate: received quit request (alreadyQuitting=\(alreadyQuitting)).")
        terminationCoordinator.beginTermination(appState: appState) {
            Self.log(
                "applicationShouldTerminate: scheduling forced exit fallback in \(Self.forcedTerminationDelay) seconds."
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.forcedTerminationDelay) {
                Self.log("applicationShouldTerminate: forced exit fallback fired.")
                Darwin.exit(0)
            }
        }
        return .terminateNow
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

            let ipcServerBox = IPCServerBox()
            let appState = self.appState
            let wm = WebhookManager(urlString: config.webhookURL)
            appState.webhookManager = wm

            // Wire callbacks before startup so initial account-connect events reach the UI.
            await orchestrator.setCallbacks(
                onNewMail: { [weak appState] accountLabel, folder in
                    ipcServerBox.value?.sendNotification(JSONRPCNotification(
                        method: "clawmail/newMail",
                        params: ["account": .string(accountLabel), "folder": .string(folder)]
                    ))
                    if let wm {
                        Task { await wm.notifyNewEmail(account: accountLabel, folder: folder) }
                    }
                    Task { @MainActor [weak appState] in
                        appState?.recordActivity("New mail detected in \(folder)", accountLabel: accountLabel)
                    }
                },
                onConnectionStatusChanged: { [weak appState] accountLabel, status in
                    ipcServerBox.value?.sendNotification(JSONRPCNotification(
                        method: "clawmail/connectionStatus",
                        params: [
                            "account": .string(accountLabel),
                            "status": .string(String(describing: status)),
                        ]
                    ))
                    Task { @MainActor [weak appState] in
                        appState?.updateConnectionStatus(status, for: accountLabel)
                        appState?.recordActivity(Self.connectionActivityMessage(for: accountLabel, status: status), accountLabel: accountLabel)
                    }
                },
                onError: { [weak appState] accountLabel, errorMessage in
                    ipcServerBox.value?.sendNotification(JSONRPCNotification(
                        method: "clawmail/error",
                        params: [
                            "account": .string(accountLabel),
                            "error": .string(errorMessage),
                        ]
                    ))
                    Task { @MainActor [weak appState] in
                        appState?.recordActivity("Error on \(accountLabel): \(errorMessage)", accountLabel: accountLabel)
                    }
                }
            )

            // Start orchestrator (connects accounts, starts sync)
            try await orchestrator.start()

            // Start IPC server (Unix domain socket)
            let ipcServer = IPCServer(orchestrator: orchestrator)
            try await ipcServer.start()
            appState.ipcServer = ipcServer
            ipcServerBox.value = ipcServer

            // Request notification permission (no-op if already granted)
            await Self.requestNotificationAuthorization()

            // Wire pending approval → macOS notification
            await orchestrator.setPendingApprovalCallback { [weak appState] accountLabel, emails in
                Task {
                    await Self.schedulePendingApprovalNotification(accountLabel: accountLabel, emails: emails)
                }
                Task { @MainActor [weak appState] in
                    appState?.recordActivity("Approval required for \(emails.joined(separator: ", "))", accountLabel: accountLabel)
                }
            }

            // Ensure API key exists (non-blocking - runs in background)
            Task.detached {
                let keychainManager = KeychainManager()
                let existingKey = await keychainManager.getAPIKey()
                if existingKey == nil {
                    do {
                        _ = try await keychainManager.generateAPIKey()
                        await MainActor.run { Self.log("Generated new REST API key") }
                    } catch {
                        let errorDesc = String(describing: error)
                        await MainActor.run { Self.log("Failed to generate API key: \(errorDesc)") }
                    }
                }
            }

            // Start REST API server
            let apiServer = APIServer(
                orchestrator: orchestrator,
                port: config.restApiPort
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
                requestSettingsWindow(selecting: .accounts, showAccountSetup: true)
            }

        } catch {
            appState.launchError = String(describing: error)
            appState.isRunning = false
        }
    }

    private static func connectionActivityMessage(for accountLabel: String, status: ConnectionStatus) -> String {
        switch status {
        case .connected:
            return "\(accountLabel) connected"
        case .connecting:
            return "\(accountLabel) connecting"
        case .disconnected:
            return "\(accountLabel) disconnected"
        case .error(let message):
            return "\(accountLabel) error: \(message)"
        }
    }

    private static func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let authorizationStatus = await notificationAuthorizationStatus(from: center)

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            return
        case .notDetermined:
            break
        @unknown default:
            return
        }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            let nsError = error as NSError
            if nsError.domain == UNErrorDomain,
               nsError.code == UNError.Code.notificationsNotAllowed.rawValue {
                return
            }
            log("Failed to request notification authorization: \(describe(error))")
        }
    }

    private static func notificationAuthorizationStatus(
        from center: UNUserNotificationCenter
    ) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestSettingsWindow(selecting tab: SettingsTab, showAccountSetup: Bool) {
        appState.settingsTab = tab
        appState.showSettings = true
        if showAccountSetup {
            appState.showAccountSetup = true
        }

        attemptToOpenSettingsWindow(attempt: 1)
    }

    private func attemptToOpenSettingsWindow(attempt: Int) {
        guard !hasVisibleStandardWindow else { return }

        let settingsOpened =
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) ||
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)

        NSApp.activate(ignoringOtherApps: true)

        guard attempt < Self.settingsAutoOpenAttempts else {
            if !settingsOpened {
                Self.log("Failed to auto-open Settings: settings action was never handled.")
            } else {
                Self.log("Failed to auto-open Settings: no visible window after \(attempt) attempts.")
            }
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: Self.settingsAutoOpenRetryDelay)
            guard !hasVisibleStandardWindow else { return }
            attemptToOpenSettingsWindow(attempt: attempt + 1)
        }
    }

    private var hasVisibleStandardWindow: Bool {
        NSApp.windows.contains { window in
            window.isVisible && !window.isMiniaturized && !(window is NSPanel)
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
