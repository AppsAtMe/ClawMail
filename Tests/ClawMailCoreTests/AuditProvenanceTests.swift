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
}
