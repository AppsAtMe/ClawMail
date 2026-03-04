import Foundation
import NIO

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

    public static var defaultSocketPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClawMail/clawmail.sock").path
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

        let handler = IPCServerHandler(orchestrator: orchestrator, server: self)

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 1)
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
final class NewlineFrameDecoder: ByteToMessageDecoder, Sendable {
    typealias InboundOut = ByteBuffer

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
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

        // Capture channel and allocator before entering Task to avoid
        // sending non-Sendable ChannelHandlerContext across isolation boundaries.
        let channel = context.channel
        let dispatcherRef = dispatcher
        let wrapFn = self.wrapOutboundOut

        Task {
            let response = await dispatcherRef.dispatch(requestData)
            guard let responseData = try? encodeJSONRPC(response) else { return }
            var outBuffer = channel.allocator.buffer(capacity: responseData.count)
            outBuffer.writeBytes(responseData)
            let noPromise: EventLoopPromise<Void>? = nil
            channel.writeAndFlush(wrapFn(outBuffer), promise: noPromise)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let noPromise: EventLoopPromise<Void>? = nil
        context.close(promise: noPromise)
    }
}
