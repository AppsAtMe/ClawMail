import Foundation

struct SyncSchedulerSnapshot: Sendable, Equatable {
    let interval: TimeInterval
    let folders: [String]
    let accountLabels: [String]
}

/// Runs periodic full reconciliation on a configurable interval.
public actor SyncScheduler {
    typealias SyncOperation = @Sendable (SyncEngine, Account, String) async throws -> Void
    typealias SleepOperation = @Sendable (Duration) async throws -> Void

    private var syncTask: Task<Void, Never>?
    private var syncEngines: [String: SyncEngine] = [:]
    private var accounts: [Account] = []
    private var interval: TimeInterval = 15 * 60 // 15 minutes
    private var folders: [String] = ["INBOX"]
    private var onError: (@Sendable (String, String) -> Void)?
    private let syncOperation: SyncOperation
    private let sleepOperation: SleepOperation

    public init() {
        self.syncOperation = { engine, account, folder in
            try await engine.incrementalSync(account: account, folder: folder)
        }
        self.sleepOperation = { duration in
            try await Task.sleep(for: duration)
        }
    }

    init(
        syncOperation: @escaping SyncOperation,
        sleepOperation: @escaping SleepOperation
    ) {
        self.syncOperation = syncOperation
        self.sleepOperation = sleepOperation
    }

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
    public func stop() async {
        let task = syncTask
        syncTask = nil
        task?.cancel()
        await task?.value
    }

    public func setErrorHandler(_ onError: (@Sendable (String, String) -> Void)?) {
        self.onError = onError
    }

    /// Trigger immediate sync for a specific account and folder.
    public func triggerSync(accountLabel: String, folder: String) async {
        guard let engine = syncEngines[accountLabel],
              let account = accounts.first(where: { $0.label == accountLabel }) else {
            return
        }
        await performSync(engine: engine, account: account, folder: folder)
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
                    await performSync(engine: engine, account: account, folder: folder)
                }
            }

            // Sleep for the configured interval
            do {
                try await sleepOperation(.seconds(interval))
            } catch is CancellationError {
                return
            } catch {
                let message = "Scheduled sync sleep failed: \(Self.describe(error))"
                fputs("ClawMail: \(message)\n", stderr)
            }
        }
    }

    private func performSync(engine: SyncEngine, account: Account, folder: String) async {
        do {
            try await syncOperation(engine, account, folder)
        } catch {
            let message = "Scheduled sync error for \(folder): \(Self.describe(error))"
            fputs("ClawMail: \(account.label): \(message)\n", stderr)
            onError?(account.label, message)
        }
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

    private static func normalizedFolders(_ folders: [String]) -> [String] {
        let normalized = folders
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else { return ["INBOX"] }

        var seen = Set<String>()
        return normalized.filter { seen.insert($0).inserted }
    }
}
