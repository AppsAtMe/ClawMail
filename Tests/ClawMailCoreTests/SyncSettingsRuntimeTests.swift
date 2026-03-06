import Foundation
import Testing
@testable import ClawMailCore

@Suite
struct SyncSettingsRuntimeTests {

    @Test func startUsesConfiguredSyncIntervalAndIdleFolders() async throws {
        let orchestrator = try AccountOrchestrator(
            config: AppConfig(
                syncIntervalMinutes: 7,
                initialSyncDays: 14,
                idleFolders: ["Projects", "INBOX"]
            ),
            databaseManager: try DatabaseManager(inMemory: true),
            configSaver: { _ in }
        )

        try await orchestrator.start()

        let snapshot = await orchestrator.syncSettingsSnapshot()
        #expect(snapshot.syncIntervalMinutes == 7)
        #expect(snapshot.initialSyncDays == 14)
        #expect(snapshot.schedulerInterval == TimeInterval(7 * 60))
        #expect(snapshot.schedulerFolders == ["Projects", "INBOX"])
        #expect(snapshot.scheduledAccounts.isEmpty)
        await orchestrator.stop()
    }

    @Test func updateSyncSettingsHotReloadsSchedulerConfiguration() async throws {
        let orchestrator = try AccountOrchestrator(
            config: AppConfig(),
            databaseManager: try DatabaseManager(inMemory: true),
            configSaver: { _ in }
        )

        try await orchestrator.start()

        try await orchestrator.updateSyncSettings(
            syncIntervalMinutes: 3,
            initialSyncDays: 21,
            idleFolders: ["Archive"]
        )

        let snapshot = await orchestrator.syncSettingsSnapshot()
        #expect(snapshot.syncIntervalMinutes == 3)
        #expect(snapshot.initialSyncDays == 21)
        #expect(snapshot.idleFolders == ["Archive"])
        #expect(snapshot.schedulerInterval == TimeInterval(3 * 60))
        #expect(snapshot.schedulerFolders == ["Archive"])
        await orchestrator.stop()
    }

    @Test func initialSyncUsesConfiguredWindowOnlyWhenStateIsMissing() async throws {
        let db = try DatabaseManager(inMemory: true)
        let account = Account(
            label: "work",
            emailAddress: "work@example.com",
            displayName: "Work",
            imapHost: "imap.example.com",
            smtpHost: "smtp.example.com",
            isEnabled: false
        )
        let orchestrator = try AccountOrchestrator(
            config: AppConfig(initialSyncDays: 12),
            databaseManager: db,
            configSaver: { _ in }
        )
        let recorder = InitialSyncRecorder()

        try await orchestrator.performInitialSyncIfNeeded(account: account) { days in
            await recorder.record(days)
        }

        let metadataIndex = MetadataIndex(db: db)
        try metadataIndex.updateSyncState(
            SyncState(accountLabel: account.label, folder: "INBOX", lastSync: Date())
        )

        try await orchestrator.performInitialSyncIfNeeded(account: account) { days in
            await recorder.record(days)
        }

        #expect(await recorder.snapshot() == [12])
    }
}

private actor InitialSyncRecorder {
    private var values: [Int] = []

    func record(_ value: Int) {
        values.append(value)
    }

    func snapshot() -> [Int] {
        values
    }
}
