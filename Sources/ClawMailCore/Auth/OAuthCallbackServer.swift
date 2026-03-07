import Foundation
import NIO
import NIOHTTP1

/// Lightweight HTTP server that listens on 127.0.0.1 for the OAuth2 callback.
///
/// Spins up on an OS-assigned random port, waits for a single GET request to
/// `/oauth/callback?code=...&state=...`, serves a "you can close this tab" page,
/// and returns the result. Automatically shuts down after receiving the callback
/// or when stopped.
public actor OAuthCallbackServer {

    /// The result delivered when the OAuth provider redirects back.
    public struct CallbackResult: Sendable {
        public let code: String
        public let state: String
    }

    private let group: EventLoopGroup
    private var channel: Channel?
    private var continuation: CheckedContinuation<CallbackResult, any Error>?

    public init() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    /// Start listening on 127.0.0.1 with an OS-assigned port.
    /// Returns the actual port and the full redirect URI to use in the authorization URL.
    public func start() async throws -> (port: Int, redirectURI: String) {
        let handler = CallbackHandler { [weak self] result in
            Task { await self?.deliverResult(result) }
        }

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 4)
            .childChannelInitializer { channel in
                do {
                    try channel.pipeline.syncOperations.addHandlers(
                        ByteToMessageHandler(HTTPRequestDecoder()),
                        HTTPResponseEncoder(),
                        handler
                    )
                    return channel.eventLoop.makeSucceededVoidFuture()
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }

        let ch = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        self.channel = ch

        guard let localAddress = ch.localAddress, let port = localAddress.port else {
            throw ClawMailError.serverError("Could not determine callback server port")
        }

        return (port: port, redirectURI: "http://127.0.0.1:\(port)/oauth/callback")
    }

    /// Wait for the OAuth callback. Times out after the specified duration.
    public func waitForCallback(timeout: Duration = .seconds(120)) async throws -> CallbackResult {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            // Set up a timeout to avoid hanging forever
            Task {
                try? await Task.sleep(for: timeout)
                self.timeoutIfWaiting()
            }
        }
    }

    /// Stop the callback server and release resources.
    public func stop() async {
        let noPromise: EventLoopPromise<Void>? = nil
        channel?.close(mode: .all, promise: noPromise)
        channel = nil
        try? await group.shutdownGracefully()
    }

    // MARK: - Internal

    private func deliverResult(_ result: CallbackResult) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: result)
    }

    private func timeoutIfWaiting() {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(throwing: ClawMailError.connectionError("OAuth callback timed out"))
    }
}

// MARK: - HTTP Handler

/// Minimal NIO HTTP handler that parses the OAuth callback and serves a response page.
private final class CallbackHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let onCallback: @Sendable (OAuthCallbackServer.CallbackResult) -> Void
    private var delivered = false

    init(onCallback: @escaping @Sendable (OAuthCallbackServer.CallbackResult) -> Void) {
        self.onCallback = onCallback
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        guard case .head(let head) = part else { return }
        guard head.method == .GET else {
            sendResponse(context: context, status: .methodNotAllowed, body: "Method not allowed")
            return
        }

        // Parse the request URI
        guard let components = URLComponents(string: head.uri) else {
            sendResponse(context: context, status: .badRequest, body: "Invalid request")
            return
        }

        // Only accept /oauth/callback
        guard components.path == "/oauth/callback" else {
            sendResponse(context: context, status: .notFound, body: "Not found")
            return
        }

        let queryItems = components.queryItems ?? []

        // Check for error from provider
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            sendResponse(
                context: context,
                status: .ok,
                body: errorPage(description)
            )
            return
        }

        // Extract code and state
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              let state = queryItems.first(where: { $0.name == "state" })?.value else {
            sendResponse(context: context, status: .badRequest, body: "Missing code or state parameter")
            return
        }

        // Serve success page before delivering the result
        if !delivered {
            delivered = true
            sendResponse(context: context, status: .ok, body: successPage)
            onCallback(OAuthCallbackServer.CallbackResult(code: code, state: state))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        let noPromise: EventLoopPromise<Void>? = nil
        context.close(promise: noPromise)
    }

    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        let bodyData = Data(body.utf8)
        let head = HTTPResponseHead(
            version: .http1_1,
            status: status,
            headers: HTTPHeaders([
                ("Content-Type", "text/html; charset=utf-8"),
                ("Content-Length", "\(bodyData.count)"),
                ("Connection", "close"),
            ])
        )
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: bodyData.count)
        buffer.writeBytes(bodyData)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private var successPage: String {
        """
        <!DOCTYPE html>
        <html><head><title>ClawMail</title><style>
        body { font-family: -apple-system, sans-serif; text-align: center; padding: 60px; background: #f5f5f7; }
        .card { background: white; border-radius: 12px; padding: 40px; max-width: 400px; margin: 0 auto; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #1d1d1f; font-size: 24px; }
        p { color: #86868b; }
        .check { font-size: 48px; margin-bottom: 16px; }
        </style></head><body>
        <div class="card">
        <div class="check">&#10003;</div>
        <h1>Authorization Successful</h1>
        <p>You can close this tab and return to ClawMail.</p>
        </div></body></html>
        """
    }

    private func errorPage(_ message: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><title>ClawMail</title><style>
        body { font-family: -apple-system, sans-serif; text-align: center; padding: 60px; background: #f5f5f7; }
        .card { background: white; border-radius: 12px; padding: 40px; max-width: 400px; margin: 0 auto; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #1d1d1f; font-size: 24px; }
        p { color: #e30000; }
        .x { font-size: 48px; margin-bottom: 16px; }
        </style></head><body>
        <div class="card">
        <div class="x">&#10007;</div>
        <h1>Authorization Failed</h1>
        <p>\(message.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</p>
        <p style="color:#86868b;">Close this tab and try again in ClawMail.</p>
        </div></body></html>
        """
    }
}
