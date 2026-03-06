import Foundation

struct SyncSchedulerSnapshot: Sendable, Equatable {
    let interval: TimeInterval
    let folders: [String]
    let accountLabels: [String]
}

/// Runs periodic full reconciliation on a configurable interval.
public actor SyncScheduler {

    private var syncTask: Task<Void, Never>?
    private var syncEngines: [String: SyncEngine] = [:]
    private var accounts: [Account] = []
    private var interval: TimeInterval = 15 * 60 // 15 minutes
    private var folders: [String] = ["INBOX"]

    public init() {}

    /// Start periodic sync for the given accounts.
    public func start(
        accounts: [Account],
        syncEngines: [String: SyncEngine],
        interval: TimeInterval = 15 * 60,
        folders: [String] = ["INBOX"]
    ) {
        self.accounts = accounts
        self.syncEngines = syncEngines
        self.interval = interval
        self.folders = Self.normalizedFolders(folders)

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

    func snapshot() -> SyncSchedulerSnapshot {
        SyncSchedulerSnapshot(
            interval: interval,
            folders: folders,
            accountLabels: accounts.map(\.label)
        )
    }

    private func syncLoop() async {
        while !Task.isCancelled {
            for account in accounts where account.isEnabled {
                guard let engine = syncEngines[account.label] else { continue }
                for folder in folders {
                    try? await engine.incrementalSync(account: account, folder: folder)
                }
            }

            // Sleep for the configured interval
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private static func normalizedFolders(_ folders: [String]) -> [String] {
        let normalized = folders
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else { return ["INBOX"] }

        var seen = Set<String>()
        return normalized.filter { seen.insert($0).inserted }
    }
}
