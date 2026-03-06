import Testing
import Foundation
@testable import ClawMailCore

/// Integration tests for the IPC layer (JSON-RPC 2.0 over Unix domain socket).
@Suite(.serialized)
struct IPCIntegrationTests {

    // MARK: - IPC Server Start/Stop

    /// Create a short temp directory for IPC test sockets (Unix sockets have a 104-byte path limit on macOS).
    private static func makeTestSocketDir() throws -> String {
        let dir = "/tmp/cm-\(UInt32.random(in: 0...0xFFFF))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func ipcServerStartsAndStops() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)

        try await server.start()

        // Verify socket file exists
        #expect(FileManager.default.fileExists(atPath: socketPath))
        // Verify token file exists
        #expect(FileManager.default.fileExists(atPath: server.tokenPath))

        await server.stop()

        // Verify socket file is cleaned up
        #expect(!FileManager.default.fileExists(atPath: socketPath))
        // Verify token file is cleaned up
        #expect(!FileManager.default.fileExists(atPath: server.tokenPath))
        await orchestrator.stop()
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func ipcServerRemovesStaleSocketFileBeforeStarting() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
        _ = FileManager.default.createFile(atPath: socketPath, contents: Data("stale".utf8))

        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        #expect(FileManager.default.fileExists(atPath: socketPath))

        await server.stop()
        await orchestrator.stop()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - IPC Client Connection

    @Test func ipcClientConnectsAndDisconnects() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        let client = IPCClient(socketPath: socketPath)
        try await client.connect()

        // Simple status request
        let response = try await client.send(method: "status", params: nil)
        // If we got here without throwing, the response was received
        #expect(response.error == nil || response.result != nil)

        await client.disconnect()
        await server.stop()
        await orchestrator.stop()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - IPC List Accounts

    @Test func ipcListAccountsReturnsEmpty() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        let client = IPCClient(socketPath: socketPath)
        try await client.connect()

        let response = try await client.send(method: "accounts.list", params: nil)
        #expect(response.error == nil)

        await client.disconnect()
        await server.stop()
        await orchestrator.stop()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - Concurrent CLI Sessions Allowed

    @Test func multipleCLIClientsCanConnectConcurrently() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        // Two CLI clients connect simultaneously — both should succeed
        let client1 = IPCClient(socketPath: socketPath, sessionType: .cli)
        let client2 = IPCClient(socketPath: socketPath, sessionType: .cli)
        try await client1.connect()
        try await client2.connect()

        // Both can execute requests
        let resp1 = try await client1.send(method: "status", params: nil)
        let resp2 = try await client2.send(method: "status", params: nil)
        #expect(resp1.error == nil)
        #expect(resp2.error == nil)

        await client1.disconnect()
        await client2.disconnect()
        await server.stop()
        await orchestrator.stop()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - Second Agent Session Is Rejected

    @Test func secondAgentClientIsRejected() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        // First agent connects
        let client1 = IPCClient(socketPath: socketPath, sessionType: .agent)
        try await client1.connect()

        // Second agent should be rejected during handshake
        let client2 = IPCClient(socketPath: socketPath, sessionType: .agent)
        do {
            try await client2.connect()
            // If connect doesn't throw, the handshake should have failed
            Issue.record("Expected second agent connection to be rejected")
        } catch {
            // Expected — handshake rejected with AGENT_ALREADY_CONNECTED
        }

        await client1.disconnect()
        await server.stop()
        await orchestrator.stop()
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - CLI Can Connect While Agent Is Active

    @Test func cliClientCanConnectWhileAgentIsActive() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        // Agent connects
        let agent = IPCClient(socketPath: socketPath, sessionType: .agent)
        try await agent.connect()

        // CLI can still connect
        let cli = IPCClient(socketPath: socketPath, sessionType: .cli)
        try await cli.connect()

        let resp = try await cli.send(method: "status", params: nil)
        #expect(resp.error == nil)

        await cli.disconnect()
        await agent.disconnect()
        await server.stop()
        await orchestrator.stop()
        try? FileManager.default.removeItem(atPath: dir)
    }
}
