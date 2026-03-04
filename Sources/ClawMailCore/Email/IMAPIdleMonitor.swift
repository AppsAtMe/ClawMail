import Foundation
import NIO

// MARK: - IMAPIdleMonitor

/// Maintains a dedicated IMAP connection for IDLE monitoring.
///
/// Watches a single folder (INBOX by default) for new mail using the IMAP IDLE
/// extension (RFC 2177). Automatically re-issues IDLE every 29 minutes and
/// reconnects on connection drops.
///
/// For MVP, monitors a single folder per connection. Multi-folder monitoring
/// would require multiple connections or cycling.
public actor IMAPIdleMonitor {

    // MARK: - Properties

    private var imapClient: IMAPClient?
    private var isRunning: Bool = false
    private var idleTask: Task<Void, Never>?
    private var host: String = ""
    private var port: Int = 993
    private var security: ConnectionSecurity = .ssl
    private var credential: IMAPCredential?
    private var monitoredFolder: String = "INBOX"
    private var onNewMail: (@Sendable (String, String) -> Void)?
    private var accountLabel: String = ""

    /// Maximum IDLE duration before re-issuing (RFC 2177 recommends < 30 min).
    private let idleTimeoutSeconds: Int = 29 * 60

    /// Delay before reconnecting after a connection failure.
    private let reconnectDelaySeconds: UInt64 = 5

    // MARK: - Initialization

    public init() {}

    // MARK: - Start / Stop

    /// Start IDLE monitoring for the given account on the specified folders.
    ///
    /// For MVP, only the first folder (or INBOX) is monitored via a single IDLE connection.
    /// The `onNewMail` callback receives (accountLabel, folderName) when new mail arrives.
    ///
    /// - Parameters:
    ///   - account: The account to monitor.
    ///   - credential: Authentication credential for the IMAP connection.
    ///   - folders: Folders to monitor (only the first is used for MVP).
    ///   - onNewMail: Callback invoked when new mail is detected.
    public func start(
        account: Account,
        credential: IMAPCredential,
        folders: [String] = ["INBOX"],
        onNewMail: @escaping @Sendable (String, String) -> Void
    ) async throws {
        guard !isRunning else { return }

        self.host = account.imapHost
        self.port = account.imapPort
        self.security = account.imapSecurity
        self.credential = credential
        self.accountLabel = account.label
        self.monitoredFolder = folders.first ?? "INBOX"
        self.onNewMail = onNewMail
        self.isRunning = true

        // Create and connect a dedicated IMAP client.
        let client = IMAPClient(
            host: host,
            port: port,
            security: security,
            credential: credential
        )
        self.imapClient = client

        try await client.connect()
        try await client.authenticate()

        // Select the folder we want to monitor.
        _ = try await client.selectFolder(monitoredFolder)

        // Start the IDLE loop in a background task.
        idleTask = Task {
            await self.idleLoop()
        }
    }

    /// Stop IDLE monitoring and disconnect.
    public func stop() async {
        isRunning = false
        idleTask?.cancel()
        idleTask = nil

        if let client = imapClient {
            await client.disconnect()
        }
        imapClient = nil
        onNewMail = nil
    }

    // MARK: - IDLE Loop

    /// Main IDLE loop that issues IDLE, waits, and re-issues periodically.
    private func idleLoop() async {
        while isRunning && !Task.isCancelled {
            do {
                try await runSingleIdleCycle()
            } catch {
                guard isRunning && !Task.isCancelled else { return }
                // Connection dropped — attempt reconnection.
                await attemptReconnect()
            }
        }
    }

    /// Run a single IDLE cycle: start IDLE, wait up to the timeout, then end IDLE.
    private func runSingleIdleCycle() async throws {
        guard let client = imapClient else { return }

        // Set up the EXISTS callback for new mail detection.
        let folder = monitoredFolder
        let label = accountLabel
        let callback = onNewMail
        await client.setExistsCallback { count in
            callback?(label, folder)
        }

        // Start IDLE.
        let tag = try await client.startIdle()

        // Wait for the idle timeout duration. New mail notifications come
        // via the EXISTS callback set above, not from this sleep.
        try await Task.sleep(nanoseconds: UInt64(idleTimeoutSeconds) * 1_000_000_000)

        // End IDLE and re-issue (the loop restarts).
        try await client.endIdle(tag: tag)
    }

    // MARK: - Reconnection

    /// Attempt to reconnect after a connection drop.
    private func attemptReconnect() async {
        guard isRunning else { return }

        // Dispose the old client.
        if let old = imapClient {
            await old.disconnect()
        }

        // Exponential backoff with a reasonable maximum.
        var delay = reconnectDelaySeconds
        let maxDelay: UInt64 = 120

        while isRunning && !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                guard isRunning else { return }

                guard let cred = credential else { return }

                let client = IMAPClient(
                    host: host,
                    port: port,
                    security: security,
                    credential: cred
                )
                self.imapClient = client

                try await client.connect()
                try await client.authenticate()
                _ = try await client.selectFolder(monitoredFolder)

                // Reconnected — return to the IDLE loop.
                return
            } catch {
                delay = min(delay * 2, maxDelay)
            }
        }
    }
}
