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

    @Test func triggerSyncReportsErrorsViaCallback() async throws {
        let recorder = SchedulerErrorRecorder()
        let scheduler = SyncScheduler(
            syncOperation: { _, _, _ in
                throw ClawMailError.serverError("manual sync failed")
            },
            sleepOperation: { _ in
                throw CancellationError()
            }
        )
        await scheduler.setErrorHandler { account, message in
            Task {
                await recorder.record(account: account, message: message)
            }
        }

        var account = testAccount(label: "work")
        account.isEnabled = false

        await scheduler.start(
            accounts: [account],
            syncEngines: ["work": try makeSyncEngine(accountLabel: "work")],
            interval: 60,
            folders: ["INBOX"]
        )

        await scheduler.triggerSync(accountLabel: "work", folder: "INBOX")
        try await Task.sleep(for: .milliseconds(50))
        await scheduler.stop()

        #expect(await recorder.records() == [
            SchedulerErrorRecord(
                account: "work",
                message: "Scheduled sync error for INBOX: Server error: manual sync failed"
            )
        ])
    }

    @Test func scheduledSyncLoopReportsErrorsViaCallback() async throws {
        let recorder = SchedulerErrorRecorder()
        let scheduler = SyncScheduler(
            syncOperation: { _, _, _ in
                throw ClawMailError.serverError("background sync failed")
            },
            sleepOperation: { _ in
                throw CancellationError()
            }
        )
        await scheduler.setErrorHandler { account, message in
            Task {
                await recorder.record(account: account, message: message)
            }
        }

        await scheduler.start(
            accounts: [testAccount(label: "work")],
            syncEngines: ["work": try makeSyncEngine(accountLabel: "work")],
            interval: 60,
            folders: ["INBOX"]
        )

        try await Task.sleep(for: .milliseconds(50))
        await scheduler.stop()

        #expect(await recorder.records() == [
            SchedulerErrorRecord(
                account: "work",
                message: "Scheduled sync error for INBOX: Server error: background sync failed"
            )
        ])
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

private struct SchedulerErrorRecord: Equatable {
    let account: String
    let message: String
}

private actor SchedulerErrorRecorder {
    private var stored: [SchedulerErrorRecord] = []

    func record(account: String, message: String) {
        stored.append(SchedulerErrorRecord(account: account, message: message))
    }

    func records() -> [SchedulerErrorRecord] {
        stored
    }
}

private func makeSyncEngine(accountLabel: String) throws -> SyncEngine {
    let imapClient = IMAPClient(
        host: "imap.example.com",
        port: 993,
        security: .ssl,
        credential: .password(username: "user@example.com", password: "secret")
    )
    let metadataIndex = MetadataIndex(db: try DatabaseManager(inMemory: true))
    return SyncEngine(imapClient: imapClient, metadataIndex: metadataIndex, accountLabel: accountLabel)
}

private func testAccount(label: String) -> Account {
    Account(
        label: label,
        emailAddress: "\(label)@example.com",
        displayName: "Test \(label)",
        imapHost: "imap.example.com",
        imapPort: 993,
        smtpHost: "smtp.example.com",
        smtpPort: 465
    )
}
