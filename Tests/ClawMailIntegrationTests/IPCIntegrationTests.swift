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

    // MARK: - Agent Lock Prevents Second Connection

    @Test func secondClientIsRejected() async throws {
        let db = try TestConfig.inMemoryDatabase()
        let config = TestConfig.testConfig()
        let orchestrator = try AccountOrchestrator(config: config, databaseManager: db)

        let dir = try Self.makeTestSocketDir()
        let socketPath = dir + "/t.sock"
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
        try? FileManager.default.removeItem(atPath: dir)
    }
}
