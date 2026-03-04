import Foundation
import NIO
import Security

/// Thread-safe box for storing a string value.
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}

/// Thread-safe box for storing channel references.
/// Used by IPCServer from both NIO event loop threads and async contexts.
private final class ChannelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _server: Channel?
    private var _client: Channel?

    var serverChannel: Channel? {
        get { lock.lock(); defer { lock.unlock() }; return _server }
        set { lock.lock(); defer { lock.unlock() }; _server = newValue }
    }

    var clientChannel: Channel? {
        get { lock.lock(); defer { lock.unlock() }; return _client }
        set { lock.lock(); defer { lock.unlock() }; _client = newValue }
    }
}

/// IPC server that listens on a Unix domain socket for JSON-RPC 2.0 requests.
///
/// The daemon (ClawMailApp) creates this server. CLI and MCP clients connect
/// to it to interact with the AccountOrchestrator.
public final class IPCServer: Sendable {

    private let socketPath: String
    private let orchestrator: AccountOrchestrator
    private let group: EventLoopGroup
    private let channels = ChannelBox()

    /// IPC authentication token. Clients must send this in an `auth.handshake` message
    /// as their first request. Stored in a thread-safe box for Sendable conformance.
    private let tokenBox = TokenBox()

    var ipcToken: String? {
        get { tokenBox.value }
        set { tokenBox.value = newValue }
    }

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static var defaultSocketPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClawMail/clawmail.sock").path
    }

    /// Path to the IPC authentication token file (co-located with the socket).
    public var tokenPath: String {
        let dir = (socketPath as NSString).deletingLastPathComponent
        return (dir as NSString).appendingPathComponent("ipc.token")
    }

    /// Token path for the default socket location (used by IPCClient).
    public static var defaultTokenPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClawMail/ipc.token").path
    }

    public init(orchestrator: AccountOrchestrator, socketPath: String? = nil) {
        self.orchestrator = orchestrator
        self.socketPath = socketPath ?? Self.defaultSocketPath
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: - Start / Stop

    public func start() async throws {
        // Remove stale socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        // Ensure the directory exists
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Generate IPC auth token and write to file with restrictive permissions
        let token = Self.generateToken()
        self.ipcToken = token
        try token.write(toFile: tokenPath, atomically: true, encoding: .utf8)
        // Set file permissions to owner-only (0600)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenPath
        )

        let handler = IPCServerHandler(orchestrator: orchestrator, server: self)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 8)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(NewlineFrameDecoder())).flatMap {
                    channel.pipeline.addHandler(handler)
                }
            }

        let channel = try await bootstrap.bind(unixDomainSocketPath: socketPath).get()
        channels.serverChannel = channel
    }

    public func stop() async {
        let ch = channels.serverChannel
        channels.serverChannel = nil
        let noPromise: EventLoopPromise<Void>? = nil
        ch?.close(mode: .all, promise: noPromise)
        try? await group.shutdownGracefully()
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: tokenPath)
        ipcToken = nil
    }

    /// Send a notification to the connected client (if any).
    public func sendNotification(_ notification: JSONRPCNotification) {
        guard let client = channels.clientChannel else { return }
        guard let data = try? encodeJSONRPC(notification) else { return }
        var buffer = client.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let noPromise: EventLoopPromise<Void>? = nil
        client.writeAndFlush(buffer, promise: noPromise)
    }

    // MARK: - Internal client management

    func setClient(_ channel: Channel?) {
        channels.clientChannel = channel
    }

    func getClient() -> Channel? {
        channels.clientChannel
    }
}

// MARK: - Newline Frame Decoder

/// Splits incoming bytes on newline boundaries (one JSON-RPC message per line).
/// Enforces a maximum frame size to prevent memory exhaustion from malicious clients.
final class NewlineFrameDecoder: ByteToMessageDecoder, Sendable {
    typealias InboundOut = ByteBuffer

    /// Maximum allowed message size (10 MB). JSON-RPC messages with email content
    /// can be large but should never exceed this.
    private static let maxFrameSize = 10 * 1024 * 1024

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        // Check if buffered data exceeds max frame size before finding a newline
        if buffer.readableBytes > Self.maxFrameSize {
            buffer.clear()
            throw ClawMailError.invalidParameter("IPC message exceeds maximum size of \(Self.maxFrameSize) bytes")
        }

        guard let newlineIndex = buffer.readableBytesView.firstIndex(of: 0x0A) else {
            return .needMoreData
        }
        let length = newlineIndex - buffer.readableBytesView.startIndex
        let frame = buffer.readSlice(length: length)!
        buffer.moveReaderIndex(forwardBy: 1) // consume the newline
        context.fireChannelRead(wrapInboundOut(frame))
        return .continue
    }
}

// MARK: - IPC Server Channel Handler

/// Handles a single client connection, dispatching JSON-RPC requests to the orchestrator.
final class IPCServerHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let orchestrator: AccountOrchestrator
    private let server: IPCServer
    private let dispatcher: IPCDispatcher
    private var authenticated = false

    init(orchestrator: AccountOrchestrator, server: IPCServer) {
        self.orchestrator = orchestrator
        self.server = server
        self.dispatcher = IPCDispatcher(orchestrator: orchestrator)
    }

    func channelActive(context: ChannelHandlerContext) {
        // Only allow one client at a time
        if server.getClient() != nil {
            let errorResponse = JSONRPCResponse.error(
                id: nil, code: JSONRPCError.agentAlreadyConnected,
                message: "Another agent session is already active"
            )
            if let responseData = try? encodeJSONRPC(errorResponse) {
                var buffer = context.channel.allocator.buffer(capacity: responseData.count)
                buffer.writeBytes(responseData)
                let noPromise: EventLoopPromise<Void>? = nil
                context.writeAndFlush(wrapOutboundOut(buffer), promise: noPromise)
            }
            let noPromise: EventLoopPromise<Void>? = nil
            context.close(promise: noPromise)
            return
        }

        server.setClient(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.setClient(nil)
        Task {
            await orchestrator.releaseAgentLock()
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else { return }
        let requestData = Data(bytes)

        // If not authenticated, the first message must be an auth.handshake
        if !authenticated {
            handleHandshake(requestData, context: context)
            return
        }

        // Capture channel and dispatcher before entering Task to avoid
        // sending non-Sendable ChannelHandlerContext across isolation boundaries.
        let channel = context.channel
        let dispatcherRef = dispatcher

        Task {
            let response = await dispatcherRef.dispatch(requestData)
            guard let responseData = try? encodeJSONRPC(response) else { return }
            var outBuffer = channel.allocator.buffer(capacity: responseData.count)
            outBuffer.writeBytes(responseData)
            let noPromise: EventLoopPromise<Void>? = nil
            channel.writeAndFlush(outBuffer, promise: noPromise)
        }
    }

    /// Validate the client's handshake message containing the IPC token.
    private func handleHandshake(_ data: Data, context: ChannelHandlerContext) {
        guard let request = try? decodeJSONRPC(JSONRPCRequest.self, from: data),
              request.method == "auth.handshake" else {
            let resp = JSONRPCResponse.error(
                id: nil, code: JSONRPCError.authFailed,
                message: "First message must be auth.handshake with a valid token"
            )
            sendAndClose(resp, context: context)
            return
        }

        guard let params = request.params,
              case .string(let token) = params["token"],
              let expected = server.ipcToken,
              Self.constantTimeEqual(token, expected) else {
            let resp = JSONRPCResponse.error(
                id: request.id, code: JSONRPCError.authFailed,
                message: "Invalid IPC authentication token"
            )
            sendAndClose(resp, context: context)
            return
        }

        authenticated = true
        let resp = JSONRPCResponse.success(id: request.id, result: .dictionary(["ok": .bool(true)]))
        if let responseData = try? encodeJSONRPC(resp) {
            var outBuffer = context.channel.allocator.buffer(capacity: responseData.count)
            outBuffer.writeBytes(responseData)
            let noPromise: EventLoopPromise<Void>? = nil
            context.writeAndFlush(wrapOutboundOut(outBuffer), promise: noPromise)
        }
    }

    /// Send a response and close the connection.
    private func sendAndClose(_ response: JSONRPCResponse, context: ChannelHandlerContext) {
        if let responseData = try? encodeJSONRPC(response) {
            var outBuffer = context.channel.allocator.buffer(capacity: responseData.count)
            outBuffer.writeBytes(responseData)
            let noPromise: EventLoopPromise<Void>? = nil
            context.writeAndFlush(wrapOutboundOut(outBuffer), promise: noPromise)
        }
        let noPromise: EventLoopPromise<Void>? = nil
        context.close(promise: noPromise)
    }

    /// Constant-time string comparison to prevent timing attacks on the IPC token.
    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(aBytes, bBytes) {
            result |= x ^ y
        }
        return result == 0
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let noPromise: EventLoopPromise<Void>? = nil
        context.close(promise: noPromise)
    }
}
