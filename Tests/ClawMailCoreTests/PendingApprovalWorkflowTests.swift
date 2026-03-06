import Foundation
import Testing
@testable import ClawMailCore

@Suite
struct PendingApprovalWorkflowTests {

    @Test func metadataIndexGroupsHeldRequestByRequestId() throws {
        let db = try DatabaseManager(inMemory: true)
        let index = MetadataIndex(db: db)

        let heldRequest = PendingApprovalRequestEnvelope(
            interface: .cli,
            payload: .send(SendEmailRequest(
                account: "work",
                to: [EmailAddress(email: "first@example.com"), EmailAddress(email: "second@example.com")],
                subject: "Quarterly report",
                body: "Attached."
            ))
        )

        try index.queuePendingApproval(
            request: heldRequest,
            emails: ["second@example.com", "first@example.com"]
        )

        let approvals = try index.listPendingApprovals(account: "work")

        #expect(approvals.count == 1)
        #expect(approvals[0].requestId == heldRequest.requestId)
        #expect(approvals[0].emails == ["first@example.com", "second@example.com"])
        #expect(approvals[0].operation == .send)
        #expect(approvals[0].subject == "Quarterly report")
    }

    @Test func approvingHeldRequestApprovesRecipientsAndReplaysOnce() async throws {
        let db = try DatabaseManager(inMemory: true)
        let index = MetadataIndex(db: db)
        let recorder = ReplayRecorder()
        var config = AppConfig()
        config.guardrails.firstTimeRecipientApproval = true

        let orchestrator = try AccountOrchestrator(
            config: config,
            databaseManager: db,
            configSaver: { _ in },
            pendingApprovalReplayHandler: { request in
                await recorder.record(request)
                return "queued-message-id"
            }
        )

        let heldRequest = PendingApprovalRequestEnvelope(
            interface: .rest,
            payload: .send(SendEmailRequest(
                account: "work",
                to: [EmailAddress(email: "new@example.com")],
                subject: "Hello",
                body: "Testing"
            ))
        )

        try index.queuePendingApproval(request: heldRequest, emails: ["new@example.com"])

        try await orchestrator.approvePendingApproval(requestId: heldRequest.requestId, account: "work")

        let replayed = await recorder.requests()
        #expect(replayed.map(\.requestId) == [heldRequest.requestId])
        #expect(replayed.map(\.interface) == [.rest])

        let approvedRecipients = try await orchestrator.listApprovedRecipients(account: "work")
        #expect(approvedRecipients.map(\.email) == ["new@example.com"])

        let pending = try await orchestrator.listPendingApprovals(account: "work")
        #expect(pending.isEmpty)

        let records = try index.pendingApprovalRecords(account: "work", status: nil)
        #expect(records.count == 1)
        #expect(records[0].status == .approved)
    }

    @Test func heldRequestReplaysOnlyAfterAllPendingRecipientsAreApproved() async throws {
        let db = try DatabaseManager(inMemory: true)
        let index = MetadataIndex(db: db)
        let recorder = ReplayRecorder()
        var config = AppConfig()
        config.guardrails.firstTimeRecipientApproval = true

        let orchestrator = try AccountOrchestrator(
            config: config,
            databaseManager: db,
            configSaver: { _ in },
            pendingApprovalReplayHandler: { request in
                await recorder.record(request)
                return "released"
            }
        )

        let heldRequest = PendingApprovalRequestEnvelope(
            interface: .cli,
            payload: .send(SendEmailRequest(
                account: "work",
                to: [EmailAddress(email: "first@example.com"), EmailAddress(email: "second@example.com")],
                subject: "Needs both approvals",
                body: "Testing"
            ))
        )

        try index.queuePendingApproval(
            request: heldRequest,
            emails: ["first@example.com", "second@example.com"]
        )

        try await orchestrator.approveRecipient(email: "first@example.com", account: "work")

        #expect(await recorder.requests().isEmpty)
        #expect((try await orchestrator.listPendingApprovals(account: "work")).count == 1)

        try await orchestrator.approveRecipient(email: "second@example.com", account: "work")

        let replayed = await recorder.requests()
        #expect(replayed.map(\.requestId) == [heldRequest.requestId])
        #expect((try await orchestrator.listPendingApprovals(account: "work")).isEmpty)
    }

    @Test func rejectingHeldRequestMarksRowsRejectedWithoutReplay() async throws {
        let db = try DatabaseManager(inMemory: true)
        let index = MetadataIndex(db: db)
        let recorder = ReplayRecorder()
        var config = AppConfig()
        config.guardrails.firstTimeRecipientApproval = true
        config.accounts = [testAccount(label: "work")]

        let orchestrator = try AccountOrchestrator(
            config: config,
            databaseManager: db,
            configSaver: { _ in },
            pendingApprovalReplayHandler: { request in
                await recorder.record(request)
                return "should-not-run"
            }
        )

        let heldRequest = PendingApprovalRequestEnvelope(
            interface: .cli,
            payload: .send(SendEmailRequest(
                account: "work",
                to: [EmailAddress(email: "new@example.com")],
                subject: "Reject me",
                body: "Testing"
            ))
        )

        try index.queuePendingApproval(request: heldRequest, emails: ["new@example.com"])

        try await orchestrator.rejectPendingApproval(requestId: heldRequest.requestId, account: "work")

        #expect(await recorder.requests().isEmpty)
        #expect((try await orchestrator.listPendingApprovals(account: "work")).isEmpty)

        let records = try index.pendingApprovalRecords(account: "work", status: nil)
        #expect(records.count == 1)
        #expect(records[0].status == .rejected)
    }

    @Test func disablingApprovalGuardrailReleasesHeldRequests() async throws {
        let db = try DatabaseManager(inMemory: true)
        let index = MetadataIndex(db: db)
        let recorder = ReplayRecorder()
        let errors = ErrorRecorder()
        var config = AppConfig()
        config.guardrails.firstTimeRecipientApproval = true
        config.accounts = [testAccount(label: "work")]

        let orchestrator = try AccountOrchestrator(
            config: config,
            databaseManager: db,
            configSaver: { _ in },
            pendingApprovalReplayHandler: { request in
                await recorder.record(request)
                return "released-after-disable"
            }
        )
        await orchestrator.setCallbacks(
            onNewMail: { _, _ in },
            onConnectionStatusChanged: { _, _ in },
            onError: { _, message in
                Task {
                    await errors.record(message)
                }
            }
        )

        let heldRequest = PendingApprovalRequestEnvelope(
            interface: .cli,
            payload: .send(SendEmailRequest(
                account: "work",
                to: [EmailAddress(email: "new@example.com")],
                subject: "Disable guardrail",
                body: "Testing"
            ))
        )

        try index.queuePendingApproval(request: heldRequest, emails: ["new@example.com"])

        await orchestrator.updateGuardrailConfig(GuardrailConfig(firstTimeRecipientApproval: false))

        let replayed = await recorder.requests()
        let recordedErrors = await errors.errors()
        if !recordedErrors.isEmpty {
            Issue.record("Errors while disabling guardrail: \(recordedErrors.joined(separator: " | "))")
        }
        #expect(replayed.map(\.requestId) == [heldRequest.requestId])
        #expect((try await orchestrator.listPendingApprovals(account: "work")).isEmpty)
    }
}

private actor ReplayRecorder {
    private var stored: [PendingApprovalRequestEnvelope] = []

    func record(_ request: PendingApprovalRequestEnvelope) {
        stored.append(request)
    }

    func requests() -> [PendingApprovalRequestEnvelope] {
        stored
    }
}

private actor ErrorRecorder {
    private var stored: [String] = []

    func record(_ message: String) {
        stored.append(message)
    }

    func errors() -> [String] {
        stored
    }
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
