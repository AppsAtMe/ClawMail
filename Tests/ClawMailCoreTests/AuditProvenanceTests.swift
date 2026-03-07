import Testing
@testable import ClawMailCore

@Suite
struct AuditProvenanceTests {

    @Test func auditSuccessUsesExplicitInterfaceEvenWhenAgentLockIsHeld() async throws {
        let db = try DatabaseManager(inMemory: true)
        let orchestrator = try AccountOrchestrator(config: AppConfig(), databaseManager: db)

        #expect(await orchestrator.acquireAgentLock(interface: .mcp))

        try await orchestrator.auditSuccess(
            interface: .rest,
            operation: "rest.write",
            account: "work",
            parameters: ["source": .string("rest")]
        )
        try await orchestrator.auditSuccess(
            interface: .cli,
            operation: "cli.write",
            account: "work",
            parameters: ["source": .string("cli")]
        )

        let entries = try await orchestrator.getAuditLog(account: "work", limit: 10, offset: 0)
        let restEntry = entries.first { $0.operation == "rest.write" }
        let cliEntry = entries.first { $0.operation == "cli.write" }

        #expect(restEntry?.interface == .rest)
        #expect(cliEntry?.interface == .cli)
    }

    @Test func ipcSessionTypeMapsToPerRequestAuditInterface() {
        #expect(IPCSessionType.cli.auditInterface == .cli)
        #expect(IPCSessionType.agent.auditInterface == .mcp)
    }

    @Test func auditLogRoundTripsAppInterfaceEntries() throws {
        let db = try DatabaseManager(inMemory: true)
        let auditLog = AuditLog(db: db)

        try auditLog.log(entry: AuditEntry(
            interface: .app,
            operation: "account.connect",
            account: "work",
            result: .success
        ))

        let entries = try auditLog.list(limit: 10)
        #expect(entries.first?.interface == .app)
        #expect(entries.first?.operation == "account.connect")
    }
}
