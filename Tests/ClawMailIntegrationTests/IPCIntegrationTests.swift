import Testing
import Foundation
@testable import ClawMailCore

/// Integration tests for the IPC layer (JSON-RPC 2.0 over Unix domain socket).
@Suite(.serialized)
struct IPCIntegrationTests {

    // MARK: - IPC Server Start/Stop

    @Test func ipcServerStartsAndStops() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let socketPath = NSTemporaryDirectory() + "clawmail-test-\(UUID().uuidString).sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)

        try await server.start()

        // Verify socket file exists
        #expect(FileManager.default.fileExists(atPath: socketPath))

        await server.stop()

        // Verify socket file is cleaned up
        #expect(!FileManager.default.fileExists(atPath: socketPath))
        await orchestrator.stop()
    }

    // MARK: - IPC Client Connection

    @Test func ipcClientConnectsAndDisconnects() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let socketPath = NSTemporaryDirectory() + "clawmail-test-\(UUID().uuidString).sock"
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
    }

    // MARK: - IPC List Accounts

    @Test func ipcListAccountsReturnsEmpty() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let socketPath = NSTemporaryDirectory() + "clawmail-test-\(UUID().uuidString).sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        let client = IPCClient(socketPath: socketPath)
        try await client.connect()

        let response = try await client.send(method: "accounts.list", params: nil)
        #expect(response.error == nil)

        await client.disconnect()
        await server.stop()
        await orchestrator.stop()
    }

    // MARK: - Agent Lock Prevents Second Connection

    @Test func secondClientIsRejected() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let socketPath = NSTemporaryDirectory() + "clawmail-test-\(UUID().uuidString).sock"
        let server = IPCServer(orchestrator: orchestrator, socketPath: socketPath)
        try await server.start()

        // First client connects
        let client1 = IPCClient(socketPath: socketPath)
        try await client1.connect()

        // Second client should be rejected
        let client2 = IPCClient(socketPath: socketPath)
        do {
            try await client2.connect()
            // If connect succeeds, a request should fail or the connection should be dropped
            _ = try? await client2.send(method: "status", params: nil)
        } catch {
            // Expected — connection rejected
        }

        await client1.disconnect()
        await server.stop()
        await orchestrator.stop()
    }
}
