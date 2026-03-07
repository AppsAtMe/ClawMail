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

/// IPC session type. CLI sessions are ephemeral and don't acquire the agent lock.
/// Agent sessions (MCP) are exclusive — only one agent can be connected at a time.
public enum IPCSessionType: String, Sendable {
    case cli
    case agent

    var auditInterface: AgentInterface {
        switch self {
        case .cli:
            return .cli
        case .agent:
            return .mcp
        }
    }
}

/// Thread-safe tracker for connected IPC clients.
/// Enforces exclusive agent sessions while allowing concurrent CLI sessions.
private final class ConnectionTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _serverChannel: Channel?
    private var _agentChannel: Channel?
    private var _cliChannels: Set<ObjectIdentifier> = []

    var serverChannel: Channel? {
        get { lock.lock(); defer { lock.unlock() }; return _serverChannel }
        set { lock.lock(); defer { lock.unlock() }; _serverChannel = newValue }
    }

    /// Try to register a new connection. Returns false if an agent session is
    /// already active and the new connection is also an agent session.
    func registerConnection(_ channel: Channel, sessionType: IPCSessionType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch sessionType {
        case .agent:
            if _agentChannel != nil { return false }
            _agentChannel = channel
            return true
        case .cli:
            _cliChannels.insert(ObjectIdentifier(channel))
            return true
        }
    }

    func unregisterConnection(_ channel: Channel, sessionType: IPCSessionType) {
        lock.lock()
        defer { lock.unlock() }
        switch sessionType {
        case .agent:
            if _agentChannel === channel {
                _agentChannel = nil
            }
        case .cli:
            _cliChannels.remove(ObjectIdentifier(channel))
        }
    }

    var hasAgentConnection: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _agentChannel != nil
    }

    /// Returns the agent channel for sending notifications.
    var agentChannel: Channel? {
        lock.lock()
        defer { lock.unlock() }
        return _agentChannel
    }
}

/// IPC server that listens on a Unix domain socket for JSON-RPC 2.0 requests.
///
/// The daemon (ClawMailApp) creates this server. CLI and MCP clients connect
/// to it to interact with the AccountOrchestrator.
///
/// Session types:
/// - `cli`: Ephemeral sessions for CLI commands. Multiple CLI sessions can
///   connect concurrently. They do not acquire the agent lock.
/// - `agent`: Exclusive sessions for MCP or long-lived agent connections.
///   Only one agent session is allowed at a time. Acquires the agent lock.
public final class IPCServer: Sendable {

    private let socketPath: String
    private let orchestrator: AccountOrchestrator
    private let group: EventLoopGroup
    private let connections = ConnectionTracker()

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
        try Self.removeItemIfPresent(atPath: socketPath)

        // Ensure the directory exists with owner-only access (0700).
        // This prevents other users from accessing the socket or token files.
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dir
        )

        // Generate IPC auth token and write to file with restrictive permissions
        let token = Self.generateToken()
        self.ipcToken = token
        try token.write(toFile: tokenPath, atomically: true, encoding: .utf8)
        // Set file permissions to owner-only (0600)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenPath
        )

        // Capture self references for the closure
        let orchestratorRef = orchestrator
        let serverRef = self

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 8)
            .childChannelInitializer { channel in
                // New handler per connection — each gets its own authenticated state
                let handler = IPCServerHandler(orchestrator: orchestratorRef, server: serverRef)
                do {
                    try channel.pipeline.syncOperations.addHandlers(
                        ByteToMessageHandler(NewlineFrameDecoder()),
                        handler
                    )
                    return channel.eventLoop.makeSucceededVoidFuture()
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }

        let channel = try await bootstrap.bind(unixDomainSocketPath: socketPath).get()
        connections.serverChannel = channel
    }

    public func stop() async {
        let ch = connections.serverChannel
        connections.serverChannel = nil
        if let ch {
            do {
                try await ch.close(mode: .all)
            } catch let error as ChannelError where error == .alreadyClosed || error == .ioOnClosedChannel {
                // Another shutdown path may have already closed the channel.
            } catch {
                Self.log("Failed to close IPC server channel: \(Self.describe(error))")
            }
        }

        do {
            try await group.shutdownGracefully()
        } catch {
            Self.log("Failed to shut down IPC server event loop: \(Self.describe(error))")
        }

        Self.cleanupItem(atPath: socketPath, description: "IPC socket")
        Self.cleanupItem(atPath: tokenPath, description: "IPC token file")
        ipcToken = nil
    }

    /// Send a notification to the connected agent client (if any).
    /// Notifications only go to agent sessions, not ephemeral CLI sessions.
    public func sendNotification(_ notification: JSONRPCNotification) {
        guard let client = connections.agentChannel else { return }
        guard let data = try? encodeJSONRPC(notification) else { return }
        var buffer = client.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let noPromise: EventLoopPromise<Void>? = nil
        client.writeAndFlush(buffer, promise: noPromise)
    }

    // MARK: - Internal connection management

    /// Try to register a connection with the given session type.
    /// Returns false if an agent session is already active and this is also an agent session.
    func registerConnection(_ channel: Channel, sessionType: IPCSessionType) -> Bool {
        connections.registerConnection(channel, sessionType: sessionType)
    }

    func unregisterConnection(_ channel: Channel, sessionType: IPCSessionType) {
        connections.unregisterConnection(channel, sessionType: sessionType)
    }

    var hasAgentConnection: Bool {
        connections.hasAgentConnection
    }

    private static func removeItemIfPresent(atPath path: String) throws {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            guard !isMissingFileError(error) else { return }
            throw error
        }
    }

    private static func cleanupItem(atPath path: String, description: String) {
        do {
            try removeItemIfPresent(atPath: path)
        } catch {
            log("Failed to remove \(description) at \(path): \(describe(error))")
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileNoSuchFile.rawValue) ||
            (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(POSIXErrorCode.ENOENT.rawValue))
    }

    private static func log(_ message: String) {
        let line = "[ClawMailIPC] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func describe(_ error: Error) -> String {
        if let clawMailError = error as? ClawMailError {
            return clawMailError.message
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
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
/// Created per-connection inside `childChannelInitializer` — each connection gets its own
/// `authenticated` flag and `sessionType`.
final class IPCServerHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let orchestrator: AccountOrchestrator
    private let server: IPCServer
    private let dispatcher: IPCDispatcher
    private var authenticated = false
    private var sessionType: IPCSessionType = .cli
    /// Result of peer credential verification (set in channelActive, checked in handleHandshake).
    /// nil = check not yet completed, true = allowed, false = rejected.
    private var peerAllowed: Bool?

    init(orchestrator: AccountOrchestrator, server: IPCServer) {
        self.orchestrator = orchestrator
        self.server = server
        self.dispatcher = IPCDispatcher(orchestrator: orchestrator)
    }

    func channelActive(context: ChannelHandlerContext) {
        // Verify connecting process via LOCAL_PEERPID (defense-in-depth).
        // Store the result for the handshake to check. The Future callback runs
        // on the same event loop, so it will complete before or during channelRead.
        if let provider = context.channel as? (any SocketOptionProvider) {
            let peerPIDFuture: EventLoopFuture<CInt> = provider.unsafeGetSocketOption(
                level: .init(rawValue: SOL_LOCAL),
                name: .init(rawValue: LOCAL_PEERPID)
            )
            peerPIDFuture.whenSuccess { [self] rawPID in
                let pid = pid_t(rawPID)
                self.peerAllowed = pid <= 0 || Self.isAllowedProcess(pid: pid)
            }
            peerPIDFuture.whenFailure { [self] _ in
                self.peerAllowed = true // Can't verify — allow, token auth is primary
            }
        } else {
            peerAllowed = true // Not a BSD socket channel — allow
        }
    }

    /// Check if the process at the given PID is a known ClawMail executable.
    ///
    /// Verifies that the connecting process is a recognized ClawMail binary by
    /// checking the executable name and path. Returns true if the process can't
    /// be identified (fail-open, since token auth is the primary mechanism).
    private static func isAllowedProcess(pid: pid_t) -> Bool {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let pathLen = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        guard pathLen > 0 else {
            // Can't determine path — allow (token auth will catch unauthorized clients)
            return true
        }
        let execPath = String(cString: pathBuffer)
        let execName = (execPath as NSString).lastPathComponent

        // Allow known ClawMail executables
        let allowedNames: Set<String> = ["ClawMailCLI", "ClawMailMCP", "ClawMailApp", "clawmail"]
        if allowedNames.contains(execName) { return true }

        // Allow processes with "ClawMail" in their path (build artifacts, test runners)
        if execPath.contains("ClawMail") { return true }

        // Allow test infrastructure and swift toolchain processes.
        // swift test runs tests via swiftpm-testing-helper or xctest.
        if execPath.contains("/swift/") || execPath.contains("/swift-") ||
           execName == "xctest" || execName.contains("swiftpm") {
            return true
        }

        return false
    }

    func channelInactive(context: ChannelHandlerContext) {
        if authenticated {
            server.unregisterConnection(context.channel, sessionType: sessionType)
            if sessionType == .agent {
                Task {
                    await orchestrator.releaseAgentLock()
                }
            }
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
        let interface = sessionType.auditInterface

        Task {
            let response = await dispatcherRef.dispatch(requestData, interface: interface)
            guard let responseData = try? encodeJSONRPC(response) else { return }
            var outBuffer = channel.allocator.buffer(capacity: responseData.count)
            outBuffer.writeBytes(responseData)
            let noPromise: EventLoopPromise<Void>? = nil
            channel.writeAndFlush(outBuffer, promise: noPromise)
        }
    }

    /// Validate the client's handshake message containing the IPC token and session type.
    ///
    /// The handshake now accepts an optional `"type"` parameter:
    /// - `"cli"` (default): Ephemeral session, no agent lock, concurrent connections allowed.
    /// - `"agent"`: Exclusive session, acquires agent lock, rejects if another agent is connected.
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

        // Defense-in-depth: check peer credential result from channelActive.
        // If the check hasn't completed yet (peerAllowed == nil), allow the
        // connection — token auth is the primary mechanism.
        if peerAllowed == false {
            let resp = JSONRPCResponse.error(
                id: request.id, code: JSONRPCError.authFailed,
                message: "Peer process is not a recognized ClawMail executable"
            )
            sendAndClose(resp, context: context)
            return
        }

        // Validate token
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

        // Determine session type from handshake params (default: cli)
        let requestedType: IPCSessionType
        if case .string(let typeStr) = params["type"], typeStr == "agent" {
            requestedType = .agent
        } else {
            requestedType = .cli
        }

        // Try to register the connection
        guard server.registerConnection(context.channel, sessionType: requestedType) else {
            let resp = JSONRPCResponse.error(
                id: request.id, code: JSONRPCError.agentAlreadyConnected,
                message: "Another agent session is already active"
            )
            sendAndClose(resp, context: context)
            return
        }

        self.sessionType = requestedType
        authenticated = true

        // Agent sessions acquire the orchestrator lock
        if requestedType == .agent {
            Task {
                _ = await orchestrator.acquireAgentLock(interface: .mcp)
            }
        }

        let resp = JSONRPCResponse.success(
            id: request.id,
            result: .dictionary([
                "ok": .bool(true),
                "sessionType": .string(requestedType.rawValue),
            ])
        )
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
