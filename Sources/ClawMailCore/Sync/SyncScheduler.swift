import Foundation

/// Runs periodic full reconciliation on a configurable interval.
public actor SyncScheduler {

    private var syncTask: Task<Void, Never>?
    private var syncEngines: [String: SyncEngine] = [:]
    private var accounts: [Account] = []
    private var interval: TimeInterval = 15 * 60 // 15 minutes

    public init() {}

    /// Start periodic sync for the given accounts.
    public func start(
        accounts: [Account],
        syncEngines: [String: SyncEngine],
        interval: TimeInterval = 15 * 60
    ) {
        self.accounts = accounts
        self.syncEngines = syncEngines
        self.interval = interval

        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncLoop()
        }
    }

    /// Stop the periodic sync.
    public func stop() {
        syncTask?.cancel()
        syncTask = nil
    }

    /// Trigger immediate sync for a specific account and folder.
    public func triggerSync(accountLabel: String, folder: String) async {
        guard let engine = syncEngines[accountLabel],
              let account = accounts.first(where: { $0.label == accountLabel }) else {
            return
        }
        try? await engine.incrementalSync(account: account, folder: folder)
    }

    private func syncLoop() async {
        while !Task.isCancelled {
            for account in accounts where account.isEnabled {
                guard let engine = syncEngines[account.label] else { continue }
                // Sync INBOX and any other configured folders
                let folders = ["INBOX"]
                for folder in folders {
                    try? await engine.incrementalSync(account: account, folder: folder)
                }
            }

            // Sleep for the configured interval
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
