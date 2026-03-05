import Foundation
import NIO

/// Client that connects to the ClawMail daemon via Unix domain socket.
///
/// Used by CLI and MCP executables to communicate with the running daemon.
/// Supports two session types:
/// - `.cli` (default): Ephemeral, doesn't acquire agent lock, concurrent connections allowed.
/// - `.agent`: Exclusive, acquires agent lock, only one at a time.
public final class IPCClient: @unchecked Sendable {

    private let socketPath: String
    private let tokenPath: String
    private let group: EventLoopGroup
    private var channel: Channel?
    private let responseHandler: IPCClientHandler

    /// The session type to use when connecting. Set before calling `connect()`.
    public var sessionType: IPCSessionType

    /// Callback for receiving notifications from the server.
    public var onNotification: (@Sendable (JSONRPCNotification) -> Void)?

    private var nextId: Int = 1

    public init(socketPath: String? = nil, tokenPath: String? = nil, sessionType: IPCSessionType = .cli) {
        let sock = socketPath ?? IPCServer.defaultSocketPath
        self.socketPath = sock
        // Default: token file is co-located with the socket
        self.tokenPath = tokenPath ?? ((sock as NSString).deletingLastPathComponent as NSString).appendingPathComponent("ipc.token")
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.responseHandler = IPCClientHandler()
        self.sessionType = sessionType
    }

    // MARK: - Connection

    public func connect() async throws {
        guard channel == nil else { return }

        let handler = responseHandler
        handler.notificationCallback = { [weak self] notification in
            self?.onNotification?(notification)
        }

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(NewlineFrameDecoder())).flatMap {
                    channel.pipeline.addHandler(handler)
                }
            }

        do {
            let ch = try await bootstrap.connect(unixDomainSocketPath: socketPath).get()
            self.channel = ch
        } catch {
            throw ClawMailError.daemonNotRunning
        }

        // Perform authentication handshake
        try await authenticate()
    }

    /// Read the IPC token from the token file and send an auth.handshake message.
    private func authenticate() async throws {
        guard let token = try? String(contentsOfFile: tokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ClawMailError.authFailed("Cannot read IPC token file at \(tokenPath)")
        }

        let response = try await send(
            method: "auth.handshake",
            params: [
                "token": .string(token),
                "type": .string(sessionType.rawValue),
            ]
        )
        if let error = response.error {
            throw ClawMailError.authFailed("IPC handshake failed: \(error.message)")
        }
    }

    /// Gracefully disconnect from the daemon.
    /// Waits for the channel close to complete before returning, ensuring the
    /// server-side `channelInactive` fires before the process exits.
    public func disconnect() async {
        guard let ch = channel else {
            try? await group.shutdownGracefully()
            return
        }
        channel = nil
        do {
            try await ch.close().get()
        } catch {
            // Channel may already be closed by the server
        }
        try? await group.shutdownGracefully()
    }

    public var isConnected: Bool {
        channel != nil && channel?.isActive == true
    }

    // MARK: - Send Request

    /// Send a JSON-RPC 2.0 request and wait for the response.
    public func send(method: String, params: [String: AnyCodableValue]? = nil) async throws -> JSONRPCResponse {
        guard let channel else {
            throw ClawMailError.daemonNotRunning
        }

        let id = JSONRPCId.int(nextId)
        nextId += 1

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let data = try encodeJSONRPC(request)

        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(buffer)

        // Wait for response with matching id
        return try await responseHandler.waitForResponse(id: id)
    }

    /// Convenience for sending a request and extracting the result or throwing on error.
    public func call(method: String, params: [String: AnyCodableValue]? = nil) async throws -> AnyCodableValue {
        let response = try await send(method: method, params: params)
        if let error = response.error {
            throw ClawMailError.serverError("\(error.message) (code: \(error.code))")
        }
        return response.result ?? .null
    }
}

// MARK: - Client Channel Handler

final class IPCClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private var pendingResponses: [JSONRPCId: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private let lock = NSLock()

    var notificationCallback: (@Sendable (JSONRPCNotification) -> Void)?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        let data = Data(bytes)

        // Try to parse as a response (has "id" field)
        if let response = try? decodeJSONRPC(JSONRPCResponse.self, from: data),
           let id = response.id {
            lock.lock()
            let continuation = pendingResponses.removeValue(forKey: id)
            lock.unlock()
            continuation?.resume(returning: response)
            return
        }

        // Try to parse as a notification (no "id" field)
        if let notification = try? decodeJSONRPC(JSONRPCNotification.self, from: data) {
            notificationCallback?(notification)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Fail all pending continuations
        lock.lock()
        let pending = pendingResponses
        pendingResponses.removeAll()
        lock.unlock()
        for (_, continuation) in pending {
            continuation.resume(throwing: error)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        lock.lock()
        let pending = pendingResponses
        pendingResponses.removeAll()
        lock.unlock()
        for (_, continuation) in pending {
            continuation.resume(throwing: ClawMailError.daemonNotRunning)
        }
    }

    /// Wait for a response with the given request id.
    func waitForResponse(id: JSONRPCId) async throws -> JSONRPCResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingResponses[id] = continuation
            lock.unlock()
        }
    }
}
