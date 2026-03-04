import Foundation
import NIO
import NIOSSL

// MARK: - IMAP Types

/// Represents an IMAP mailbox (folder).
public struct IMAPFolder: Sendable, Equatable {
    public var name: String
    public var delimiter: Character?
    public var attributes: Set<String>
    public var children: [IMAPFolder]

    public init(
        name: String,
        delimiter: Character? = nil,
        attributes: Set<String> = [],
        children: [IMAPFolder] = []
    ) {
        self.name = name
        self.delimiter = delimiter
        self.attributes = attributes
        self.children = children
    }

    public var isSelectable: Bool {
        !attributes.contains("\\Noselect") && !attributes.contains("\\NonExistent")
    }
}

/// Status information returned after selecting a mailbox.
public struct MailboxStatus: Sendable, Equatable {
    public var exists: Int
    public var recent: Int
    public var unseen: Int?
    public var uidValidity: UInt32
    public var uidNext: UInt32?
    public var highestModSeq: UInt64?

    public init(
        exists: Int = 0,
        recent: Int = 0,
        unseen: Int? = nil,
        uidValidity: UInt32 = 0,
        uidNext: UInt32? = nil,
        highestModSeq: UInt64? = nil
    ) {
        self.exists = exists
        self.recent = recent
        self.unseen = unseen
        self.uidValidity = uidValidity
        self.uidNext = uidNext
        self.highestModSeq = highestModSeq
    }
}

/// Envelope data for an IMAP message summary.
public struct IMAPEnvelope: Sendable, Equatable {
    public var date: Date?
    public var subject: String?
    public var from: [EmailAddress]
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var messageId: String?
    public var inReplyTo: String?

    public init(
        date: Date? = nil,
        subject: String? = nil,
        from: [EmailAddress] = [],
        to: [EmailAddress] = [],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        messageId: String? = nil,
        inReplyTo: String? = nil
    ) {
        self.date = date
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.messageId = messageId
        self.inReplyTo = inReplyTo
    }
}

/// Summary of a message fetched from IMAP (flags + envelope + bodystructure + size).
public struct IMAPMessageSummary: Sendable, Equatable {
    public var uid: UInt32
    public var flags: Set<EmailFlag>
    public var envelope: IMAPEnvelope
    public var size: Int?
    public var hasAttachments: Bool
    public var bodyStructureRaw: String?

    public init(
        uid: UInt32,
        flags: Set<EmailFlag> = [],
        envelope: IMAPEnvelope = IMAPEnvelope(),
        size: Int? = nil,
        hasAttachments: Bool = false,
        bodyStructureRaw: String? = nil
    ) {
        self.uid = uid
        self.flags = flags
        self.envelope = envelope
        self.size = size
        self.hasAttachments = hasAttachments
        self.bodyStructureRaw = bodyStructureRaw
    }
}

/// Raw MIME body data of a fetched message.
public struct IMAPMessageBody: Sendable, Equatable {
    public var rawData: Data
    public var uid: UInt32

    public init(rawData: Data, uid: UInt32) {
        self.rawData = rawData
        self.uid = uid
    }
}

/// Criteria for IMAP SEARCH commands.
public indirect enum IMAPSearchCriteria: Sendable, Equatable {
    case all
    case unseen
    case seen
    case flagged
    case unflagged
    case answered
    case deleted
    case from(String)
    case to(String)
    case subject(String)
    case body(String)
    case before(Date)
    case since(Date)
    case on(Date)
    case header(String, String)
    case uid(ClosedRange<UInt32>)
    case larger(Int)
    case smaller(Int)
    case and(IMAPSearchCriteria, IMAPSearchCriteria)
    case or(IMAPSearchCriteria, IMAPSearchCriteria)
    case not(IMAPSearchCriteria)

    /// Render to IMAP SEARCH command syntax.
    /// All string values are sanitized to prevent IMAP command injection (CRLF stripping + quote escaping).
    public func commandString() -> String {
        let formatter = IMAPDateFormatter.searchDateFormatter
        switch self {
        case .all: return "ALL"
        case .unseen: return "UNSEEN"
        case .seen: return "SEEN"
        case .flagged: return "FLAGGED"
        case .unflagged: return "UNFLAGGED"
        case .answered: return "ANSWERED"
        case .deleted: return "DELETED"
        case .from(let s): return "FROM \(Self.quoteSearchString(s))"
        case .to(let s): return "TO \(Self.quoteSearchString(s))"
        case .subject(let s): return "SUBJECT \(Self.quoteSearchString(s))"
        case .body(let s): return "BODY \(Self.quoteSearchString(s))"
        case .before(let d): return "BEFORE \(formatter.string(from: d))"
        case .since(let d): return "SINCE \(formatter.string(from: d))"
        case .on(let d): return "ON \(formatter.string(from: d))"
        case .header(let name, let value): return "HEADER \(Self.quoteSearchString(name)) \(Self.quoteSearchString(value))"
        case .uid(let range): return "UID \(range.lowerBound):\(range.upperBound)"
        case .larger(let n): return "LARGER \(n)"
        case .smaller(let n): return "SMALLER \(n)"
        case .and(let a, let b): return "\(a.commandString()) \(b.commandString())"
        case .or(let a, let b): return "OR (\(a.commandString())) (\(b.commandString()))"
        case .not(let c): return "NOT (\(c.commandString()))"
        }
    }

    /// Quote and sanitize a string for IMAP SEARCH criteria.
    /// Strips CR/LF to prevent command injection, escapes backslash and double-quote.
    private static func quoteSearchString(_ s: String) -> String {
        let sanitized = s.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let escaped = sanitized.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// A UID range used for FETCH operations.
public struct UIDRange: Sendable, Equatable {
    public var start: UInt32
    public var end: UInt32?

    public init(start: UInt32, end: UInt32? = nil) {
        self.start = start
        self.end = end
    }

    /// "start:end" or "start:*"
    public var rangeString: String {
        if let end = end {
            return "\(start):\(end)"
        }
        return "\(start):*"
    }
}

// MARK: - IMAPDateFormatter

/// Thread-safe date formatter for IMAP date strings.
private enum IMAPDateFormatter {
    static let searchDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

/// Credential type for IMAP authentication.
public enum IMAPCredential: Sendable {
    case password(username: String, password: String)
    case oauth2(username: String, accessToken: String)
}

// MARK: - IMAPResponseHandler (NIO ChannelHandler)

/// Actor-based line buffer that bridges NIO event loop callbacks to async/await.
/// Lines produced by the NIO handler are enqueued here and consumed by the IMAPClient.
private actor IMAPLineBuffer {
    private var lines: [String] = []
    private var waiters: [CheckedContinuation<String, any Error>] = []
    private var isClosed = false

    func enqueue(_ line: String) {
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: line)
        } else {
            lines.append(line)
        }
    }

    func close(error: (any Error)? = nil) {
        isClosed = true
        let pendingWaiters = waiters
        waiters.removeAll()
        let err = error ?? ClawMailError.connectionError("Connection closed")
        for waiter in pendingWaiters {
            waiter.resume(throwing: err)
        }
    }

    func readLine() async throws -> String {
        if !lines.isEmpty {
            return lines.removeFirst()
        }
        if isClosed {
            throw ClawMailError.connectionError("Connection closed")
        }
        return try await withCheckedThrowingContinuation { continuation in
            if isClosed {
                continuation.resume(throwing: ClawMailError.connectionError("Connection closed"))
            } else {
                waiters.append(continuation)
            }
        }
    }
}

/// Collects raw IMAP response lines from the server and enqueues them
/// in an IMAPLineBuffer for async consumption by the IMAPClient actor.
private final class IMAPResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private var lineBuffer: String = ""
    let lineQueue: IMAPLineBuffer
    var onUnsolicitedExists: (@Sendable (Int) -> Void)?

    init(lineQueue: IMAPLineBuffer) {
        self.lineQueue = lineQueue
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        guard let text = buf.readString(length: buf.readableBytes) else { return }

        lineBuffer.append(text)

        // Extract complete lines (terminated by \r\n).
        while let crlfRange = lineBuffer.range(of: "\r\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<crlfRange.lowerBound])
            lineBuffer = String(lineBuffer[crlfRange.upperBound...])

            // Detect unsolicited EXISTS notifications for IDLE.
            if line.contains("EXISTS") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 2, parts[0] == "*", let count = Int(parts[1]) {
                    onUnsolicitedExists?(count)
                }
            }

            // Enqueue line asynchronously. We create a detached task because
            // we are on the NIO event loop (synchronous) and need to call
            // the actor-isolated enqueue method.
            let queue = lineQueue
            Task { await queue.enqueue(line) }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        let queue = lineQueue
        Task { await queue.close() }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        let queue = lineQueue
        let desc = String(describing: error)
        Task { await queue.close(error: ClawMailError.connectionError("IMAP: \(desc)")) }
        context.close(promise: nil)
    }
}

// MARK: - IMAPClient Actor

/// IMAP4rev1 client implemented directly over SwiftNIO + NIOSSL.
///
/// Serializes all connection access through Swift actor isolation.
/// Supports SSL/TLS and STARTTLS, LOGIN and XOAUTH2 authentication,
/// mailbox management, message fetch/search/move/delete/flag operations,
/// and CONDSTORE-based sync.
public actor IMAPClient {

    // MARK: - Properties

    private let host: String
    private let port: Int
    private let security: ConnectionSecurity
    private let credential: IMAPCredential

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var responseHandler: IMAPResponseHandler?
    private var lineBuffer: IMAPLineBuffer?
    private var tagCounter: Int = 0
    private var _isConnected: Bool = false
    private var selectedFolder: String?

    /// Whether the client is currently connected.
    public var isConnected: Bool { _isConnected }

    // MARK: - Initialization

    public init(
        host: String,
        port: Int,
        security: ConnectionSecurity,
        credential: IMAPCredential
    ) {
        self.host = host
        self.port = port
        self.security = security
        self.credential = credential
    }

    // MARK: - Tag Generation

    private func nextTag() -> String {
        tagCounter += 1
        return "T\(tagCounter)"
    }

    // MARK: - Connection Management

    /// Establish a connection to the IMAP server with TLS.
    public func connect() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        // Create the line buffer for async line reading.
        let queue = IMAPLineBuffer()
        self.lineBuffer = queue

        let handler = IMAPResponseHandler(lineQueue: queue)
        self.responseHandler = handler

        let useTLS = (security == .ssl)
        let hostname = self.host

        let sslContext: NIOSSLContext?
        if useTLS {
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .fullVerification
            // Use the system certificate store (macOS Keychain) for trust evaluation
            config.trustRoots = .default
            sslContext = try NIOSSLContext(configuration: config)
        } else {
            sslContext = nil
        }

        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(15))
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                var handlers: [any ChannelHandler] = []
                if let ctx = sslContext {
                    do {
                        let sslHandler = try NIOSSLClientHandler(context: ctx, serverHostname: hostname)
                        handlers.append(sslHandler)
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
                handlers.append(handler)
                return channel.pipeline.addHandlers(handlers)
            }

        do {
            let ch = try await bootstrap.connect(host: host, port: port).get()
            self.channel = ch

            // Read the server greeting.
            let greeting = try await readLine()
            guard greeting.hasPrefix("* OK") else {
                throw ClawMailError.connectionError("Unexpected greeting: \(greeting)")
            }

            // If STARTTLS, upgrade the connection now.
            if security == .starttls {
                try await upgradeToTLS(channel: ch)
            }

            _isConnected = true
        } catch let error as ClawMailError {
            throw error
        } catch {
            throw ClawMailError.connectionError(String(describing: error))
        }
    }

    /// Upgrade a plaintext connection to TLS (STARTTLS).
    private func upgradeToTLS(channel: Channel) async throws {
        let tag = nextTag()
        try await sendRaw("\(tag) STARTTLS\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.connectionError("STARTTLS failed: \(response.text)")
        }

        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .fullVerification
        config.trustRoots = .default
        let sslContext = try NIOSSLContext(configuration: config)
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)

        try await channel.pipeline.addHandler(sslHandler, position: .first).get()
    }

    /// Authenticate using LOGIN or XOAUTH2.
    public func authenticate() async throws {
        guard _isConnected else {
            throw ClawMailError.connectionError("Not connected")
        }

        switch credential {
        case .password(let username, let password):
            try await loginAuthenticate(username: username, password: password)
        case .oauth2(let username, let accessToken):
            try await xoauth2Authenticate(username: username, accessToken: accessToken)
        }
    }

    private func loginAuthenticate(username: String, password: String) async throws {
        let tag = nextTag()
        // Quote and escape username/password for the LOGIN command.
        let escapedUser = username.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPass = password.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        try await sendRaw("\(tag) LOGIN \"\(escapedUser)\" \"\(escapedPass)\"\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.authFailed("LOGIN failed: \(response.text)")
        }
    }

    private func xoauth2Authenticate(username: String, accessToken: String) async throws {
        let tag = nextTag()
        let authString = "user=\(username)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        let encoded = Data(authString.utf8).base64EncodedString()
        try await sendRaw("\(tag) AUTHENTICATE XOAUTH2 \(encoded)\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.authFailed("XOAUTH2 failed: \(response.text)")
        }
    }

    /// Disconnect from the server gracefully.
    public func disconnect() async {
        if _isConnected, channel != nil {
            let tag = nextTag()
            try? await sendRaw("\(tag) LOGOUT\r\n")
            // Read any remaining responses but don't fail if connection drops.
            _ = try? await readTaggedResponse(tag: tag)
        }
        _isConnected = false
        selectedFolder = nil
        try? await channel?.close().get()
        channel = nil
        if let buf = lineBuffer {
            await buf.close()
        }
        lineBuffer = nil
        responseHandler = nil
        if let group = eventLoopGroup {
            eventLoopGroup = nil
            group.shutdownGracefully { _ in }
        }
    }

    /// Reconnect to the server (disconnect then connect + authenticate).
    public func reconnect() async throws {
        await disconnect()
        try await connect()
        try await authenticate()
    }

    // MARK: - Low-Level I/O

    private func sendRaw(_ text: String) async throws {
        guard let channel = channel else {
            throw ClawMailError.connectionError("No active channel")
        }
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        try await channel.writeAndFlush(buffer).get()
    }

    private func readLine() async throws -> String {
        guard let buf = lineBuffer else {
            throw ClawMailError.connectionError("No response stream")
        }
        return try await buf.readLine()
    }

    // MARK: - Response Parsing

    private enum ResponseStatus {
        case ok, no, bad
    }

    private struct TaggedResponse {
        var status: ResponseStatus
        var text: String
        var untaggedLines: [String]
    }

    /// Read lines until the tagged response for `tag` is found.
    /// Returns all untagged lines collected along the way plus the tagged result.
    private func readTaggedResponse(tag: String) async throws -> TaggedResponse {
        var untaggedLines: [String] = []

        while true {
            let line = try await readLine()

            if line.hasPrefix(tag + " ") {
                let rest = String(line.dropFirst(tag.count + 1))
                if rest.hasPrefix("OK") {
                    return TaggedResponse(status: .ok, text: rest, untaggedLines: untaggedLines)
                } else if rest.hasPrefix("NO") {
                    return TaggedResponse(status: .no, text: rest, untaggedLines: untaggedLines)
                } else if rest.hasPrefix("BAD") {
                    return TaggedResponse(status: .bad, text: rest, untaggedLines: untaggedLines)
                }
                return TaggedResponse(status: .ok, text: rest, untaggedLines: untaggedLines)
            }

            // Continuation request line (literal data).
            if line.hasPrefix("+") {
                untaggedLines.append(line)
                continue
            }

            // Untagged response.
            untaggedLines.append(line)
        }
    }

    /// Read a literal block of `count` bytes following a {N} marker in a response.
    /// Accumulates lines until enough data is collected.
    private func readLiteralData(byteCount: Int) async throws -> Data {
        var accumulated = Data()
        while accumulated.count < byteCount {
            let line = try await readLine()
            let lineData = Data((line + "\r\n").utf8)
            accumulated.append(lineData)
        }
        return Data(accumulated.prefix(byteCount))
    }

    /// Read all untagged lines for a tagged command, collecting literal data
    /// that follows `{N}` markers on FETCH responses.
    private func readTaggedResponseWithLiterals(tag: String) async throws -> (TaggedResponse, [Data]) {
        var untaggedLines: [String] = []
        var literalChunks: [Data] = []

        while true {
            let line = try await readLine()

            if line.hasPrefix(tag + " ") {
                let rest = String(line.dropFirst(tag.count + 1))
                let status: ResponseStatus
                if rest.hasPrefix("OK") {
                    status = .ok
                } else if rest.hasPrefix("NO") {
                    status = .no
                } else if rest.hasPrefix("BAD") {
                    status = .bad
                } else {
                    status = .ok
                }
                let tr = TaggedResponse(status: status, text: rest, untaggedLines: untaggedLines)
                return (tr, literalChunks)
            }

            // Check for literal marker {N}.
            if let literalCount = extractLiteralCount(from: line) {
                untaggedLines.append(line)
                let data = try await readLiteralData(byteCount: literalCount)
                literalChunks.append(data)
            } else {
                untaggedLines.append(line)
            }
        }
    }

    /// Extract literal byte count from a line ending in `{N}`.
    private func extractLiteralCount(from line: String) -> Int? {
        guard line.hasSuffix("}") else { return nil }
        guard let openBrace = line.lastIndex(of: "{") else { return nil }
        let start = line.index(after: openBrace)
        let end = line.index(before: line.endIndex)
        guard start < end else { return nil }
        let numberStr = String(line[start..<end])
        return Int(numberStr)
    }

    // MARK: - Mailbox Operations

    /// List all IMAP folders (mailboxes).
    public func listFolders() async throws -> [IMAPFolder] {
        try ensureConnected()

        let tag = nextTag()
        try await sendRaw("\(tag) LIST \"\" \"*\"\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.serverError("LIST failed: \(response.text)")
        }

        var folders: [IMAPFolder] = []
        for line in response.untaggedLines {
            if let folder = parseListResponse(line) {
                folders.append(folder)
            }
        }
        return folders
    }

    /// Parse a `* LIST (\Attributes) "delimiter" "name"` response line.
    private func parseListResponse(_ line: String) -> IMAPFolder? {
        guard line.hasPrefix("* LIST ") || line.hasPrefix("* LSUB ") else { return nil }
        let content = String(line.dropFirst(7))

        // Parse attributes in parentheses.
        guard let openParen = content.firstIndex(of: "("),
              let closeParen = content.firstIndex(of: ")") else { return nil }

        let attrsStr = String(content[content.index(after: openParen)..<closeParen])
        let attributes = Set(
            attrsStr.components(separatedBy: " ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        // After the closing paren: ` "delimiter" "name"` or ` NIL "name"`.
        let rest = String(content[content.index(after: closeParen)...]).trimmingCharacters(in: .whitespaces)
        let parts = rest.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        // Delimiter.
        let delimiterStr = parts[0]
        let delimiter: Character?
        if delimiterStr == "NIL" {
            delimiter = nil
        } else {
            let stripped = delimiterStr.replacingOccurrences(of: "\"", with: "")
            delimiter = stripped.first
        }

        // Folder name -- may be quoted or unquoted.
        let namePart = parts.dropFirst().joined(separator: " ")
        let name = unquoteIMAPString(namePart)

        return IMAPFolder(name: name, delimiter: delimiter, attributes: attributes)
    }

    /// Select a folder and return its status.
    public func selectFolder(_ name: String) async throws -> MailboxStatus {
        try ensureConnected()

        let tag = nextTag()
        let quotedName = quoteIMAPString(name)
        try await sendRaw("\(tag) SELECT \(quotedName)\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.folderNotFound("SELECT failed for '\(name)': \(response.text)")
        }

        selectedFolder = name
        return parseMailboxStatus(from: response)
    }

    /// Create a new folder.
    public func createFolder(_ name: String) async throws {
        try ensureConnected()

        let tag = nextTag()
        let quotedName = quoteIMAPString(name)
        try await sendRaw("\(tag) CREATE \(quotedName)\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.serverError("CREATE failed: \(response.text)")
        }
    }

    /// Delete a folder.
    public func deleteFolder(_ name: String) async throws {
        try ensureConnected()

        let tag = nextTag()
        let quotedName = quoteIMAPString(name)
        try await sendRaw("\(tag) DELETE \(quotedName)\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.serverError("DELETE failed: \(response.text)")
        }
    }

    // MARK: - Message Operations

    /// Fetch message summaries (envelope, flags, size) for a UID range.
    public func fetchMessageSummaries(folder: String, range: UIDRange) async throws -> [IMAPMessageSummary] {
        try ensureConnected()
        if selectedFolder != folder {
            _ = try await selectFolder(folder)
        }

        let tag = nextTag()
        try await sendRaw("\(tag) UID FETCH \(range.rangeString) (FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE)\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.serverError("FETCH summaries failed: \(response.text)")
        }

        return parseFetchSummaries(from: response.untaggedLines)
    }

    /// Fetch the full RFC822 body of a message by UID.
    public func fetchMessageBody(folder: String, uid: UInt32) async throws -> IMAPMessageBody {
        try ensureConnected()
        if selectedFolder != folder {
            _ = try await selectFolder(folder)
        }

        let tag = nextTag()
        try await sendRaw("\(tag) UID FETCH \(uid) BODY.PEEK[]\r\n")
        let (response, literals) = try await readTaggedResponseWithLiterals(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.messageNotFound("FETCH body failed for UID \(uid): \(response.text)")
        }

        // The body data is typically in the first literal chunk.
        if let data = literals.first {
            return IMAPMessageBody(rawData: data, uid: uid)
        }

        // Fallback: reconstruct from untagged lines.
        let bodyText = response.untaggedLines.joined(separator: "\r\n")
        return IMAPMessageBody(rawData: Data(bodyText.utf8), uid: uid)
    }

    /// Fetch just the headers of a message by UID.
    public func fetchMessageHeaders(folder: String, uid: UInt32) async throws -> [String: String] {
        try ensureConnected()
        if selectedFolder != folder {
            _ = try await selectFolder(folder)
        }

        let tag = nextTag()
        try await sendRaw("\(tag) UID FETCH \(uid) BODY.PEEK[HEADER]\r\n")
        let (response, literals) = try await readTaggedResponseWithLiterals(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.messageNotFound("FETCH headers failed for UID \(uid): \(response.text)")
        }

        let headerText: String
        if let data = literals.first, let s = String(data: data, encoding: .utf8) {
            headerText = s
        } else {
            headerText = response.untaggedLines.joined(separator: "\r\n")
        }
        return MIMEParser.parseHeaders(headerText)
    }

    /// Search messages in a folder using the given criteria.
    public func searchMessages(folder: String, criteria: IMAPSearchCriteria) async throws -> [UInt32] {
        try ensureConnected()
        if selectedFolder != folder {
            _ = try await selectFolder(folder)
        }

        let tag = nextTag()
        try await sendRaw("\(tag) UID SEARCH \(criteria.commandString())\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.serverError("SEARCH failed: \(response.text)")
        }

        // Parse "* SEARCH uid1 uid2 ..." lines.
        var uids: [UInt32] = []
        for line in response.untaggedLines {
            if line.hasPrefix("* SEARCH") {
                let parts = line.dropFirst("* SEARCH".count)
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                for part in parts {
                    if let uid = UInt32(part) {
                        uids.append(uid)
                    }
                }
            }
        }
        return uids
    }

    /// Move a message from one folder to another. Uses MOVE if supported, otherwise COPY+DELETE.
    public func moveMessage(uid: UInt32, from: String, to: String) async throws {
        try ensureConnected()
        if selectedFolder != from {
            _ = try await selectFolder(from)
        }

        // Try MOVE first (RFC 6851).
        let moveTag = nextTag()
        let quotedTo = quoteIMAPString(to)
        try await sendRaw("\(moveTag) UID MOVE \(uid) \(quotedTo)\r\n")
        let moveResponse = try await readTaggedResponse(tag: moveTag)
        if moveResponse.status == .ok {
            return
        }

        // Fallback: COPY then flag \Deleted then EXPUNGE.
        let copyTag = nextTag()
        try await sendRaw("\(copyTag) UID COPY \(uid) \(quotedTo)\r\n")
        let copyResponse = try await readTaggedResponse(tag: copyTag)
        guard copyResponse.status == .ok else {
            throw ClawMailError.serverError("COPY failed: \(copyResponse.text)")
        }

        let storeTag = nextTag()
        try await sendRaw("\(storeTag) UID STORE \(uid) +FLAGS (\\Deleted)\r\n")
        _ = try await readTaggedResponse(tag: storeTag)

        let expungeTag = nextTag()
        try await sendRaw("\(expungeTag) EXPUNGE\r\n")
        _ = try await readTaggedResponse(tag: expungeTag)
    }

    /// Delete a message. If `permanent` is true, flag \Deleted and EXPUNGE.
    /// Otherwise, move to Trash folder.
    public func deleteMessage(uid: UInt32, folder: String, permanent: Bool = false) async throws {
        try ensureConnected()

        if permanent {
            if selectedFolder != folder {
                _ = try await selectFolder(folder)
            }
            let storeTag = nextTag()
            try await sendRaw("\(storeTag) UID STORE \(uid) +FLAGS (\\Deleted)\r\n")
            let storeResp = try await readTaggedResponse(tag: storeTag)
            guard storeResp.status == .ok else {
                throw ClawMailError.serverError("STORE \\Deleted failed: \(storeResp.text)")
            }
            let expungeTag = nextTag()
            try await sendRaw("\(expungeTag) EXPUNGE\r\n")
            let expResp = try await readTaggedResponse(tag: expungeTag)
            guard expResp.status == .ok else {
                throw ClawMailError.serverError("EXPUNGE failed: \(expResp.text)")
            }
        } else {
            // Move to Trash.
            try await moveMessage(uid: uid, from: folder, to: "Trash")
        }
    }

    /// Update flags on a message (add and/or remove).
    public func updateFlags(uid: UInt32, folder: String, add: [EmailFlag] = [], remove: [EmailFlag] = []) async throws {
        try ensureConnected()
        if selectedFolder != folder {
            _ = try await selectFolder(folder)
        }

        if !add.isEmpty {
            let flagStr = add.map { emailFlagToIMAPFlag($0) }.joined(separator: " ")
            let tag = nextTag()
            try await sendRaw("\(tag) UID STORE \(uid) +FLAGS (\(flagStr))\r\n")
            let resp = try await readTaggedResponse(tag: tag)
            guard resp.status == .ok else {
                throw ClawMailError.serverError("STORE +FLAGS failed: \(resp.text)")
            }
        }

        if !remove.isEmpty {
            let flagStr = remove.map { emailFlagToIMAPFlag($0) }.joined(separator: " ")
            let tag = nextTag()
            try await sendRaw("\(tag) UID STORE \(uid) -FLAGS (\(flagStr))\r\n")
            let resp = try await readTaggedResponse(tag: tag)
            guard resp.status == .ok else {
                throw ClawMailError.serverError("STORE -FLAGS failed: \(resp.text)")
            }
        }
    }

    /// Fetch a specific MIME section (e.g. attachment data) by section number.
    /// Section must be a valid MIME section specifier (digits and dots only, e.g. "1", "1.2", "2.1.3").
    public func fetchAttachment(folder: String, uid: UInt32, section: String) async throws -> Data {
        // Validate section before any network I/O — prevents injection even if not connected
        let sectionPattern = /^[0-9]+(\.[0-9]+)*$/
        guard section.wholeMatch(of: sectionPattern) != nil else {
            throw ClawMailError.invalidParameter("Invalid MIME section specifier: \(section)")
        }

        try ensureConnected()
        if selectedFolder != folder {
            _ = try await selectFolder(folder)
        }

        let tag = nextTag()
        try await sendRaw("\(tag) UID FETCH \(uid) BODY.PEEK[\(section)]\r\n")
        let (response, literals) = try await readTaggedResponseWithLiterals(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.messageNotFound("FETCH attachment failed for UID \(uid) section \(section)")
        }

        if let data = literals.first {
            return data
        }

        let text = response.untaggedLines.joined(separator: "\r\n")
        return Data(text.utf8)
    }

    // MARK: - Sync Support

    /// Get the UIDVALIDITY for a folder.
    public func getUIDValidity(folder: String) async throws -> UInt32 {
        let status = try await selectFolder(folder)
        return status.uidValidity
    }

    /// Get the highest CONDSTORE mod-sequence for a folder (if supported).
    public func getHighestModSeq(folder: String) async throws -> UInt64? {
        let status = try await selectFolder(folder)
        return status.highestModSeq
    }

    /// Fetch messages changed since the given mod-sequence (CONDSTORE/QRESYNC).
    public func fetchChangedSince(folder: String, modSeq: UInt64) async throws -> [IMAPMessageSummary] {
        try ensureConnected()
        if selectedFolder != folder {
            _ = try await selectFolder(folder)
        }

        let tag = nextTag()
        try await sendRaw("\(tag) UID FETCH 1:* (FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE) (CHANGEDSINCE \(modSeq))\r\n")
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw ClawMailError.serverError("FETCH CHANGEDSINCE failed: \(response.text)")
        }

        return parseFetchSummaries(from: response.untaggedLines)
    }

    // MARK: - NOOP (keepalive / poll)

    /// Send a NOOP command to keep the connection alive and poll for status changes.
    public func noop() async throws {
        try ensureConnected()
        let tag = nextTag()
        try await sendRaw("\(tag) NOOP\r\n")
        _ = try await readTaggedResponse(tag: tag)
    }

    // MARK: - IDLE Support (for IMAPIdleMonitor)

    /// Send the IDLE command. Returns the tag used (needed to send DONE).
    public func startIdle() async throws -> String {
        try ensureConnected()
        let tag = nextTag()
        try await sendRaw("\(tag) IDLE\r\n")
        // Read the continuation response "+".
        let line = try await readLine()
        guard line.hasPrefix("+") else {
            throw ClawMailError.serverError("IDLE not accepted: \(line)")
        }
        return tag
    }

    /// End an IDLE session by sending DONE and reading the tagged response.
    public func endIdle(tag: String) async throws {
        try await sendRaw("DONE\r\n")
        _ = try await readTaggedResponse(tag: tag)
    }

    /// Set a callback for unsolicited EXISTS notifications (used by IDLE monitor).
    public func setExistsCallback(_ callback: @escaping @Sendable (Int) -> Void) {
        responseHandler?.onUnsolicitedExists = callback
    }

    // MARK: - Helpers

    private func ensureConnected() throws {
        guard _isConnected else {
            throw ClawMailError.connectionError("Not connected to IMAP server")
        }
    }

    /// Quote a string for safe inclusion in IMAP commands.
    /// Strips CR/LF to prevent IMAP command injection, then escapes backslash and double-quote.
    func quoteIMAPString(_ s: String) -> String {
        let sanitized = s.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let escaped = sanitized.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func unquoteIMAPString(_ s: String) -> String {
        var result = s.trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("\"") && result.hasSuffix("\"") {
            result = String(result.dropFirst().dropLast())
        }
        return result.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func emailFlagToIMAPFlag(_ flag: EmailFlag) -> String {
        switch flag {
        case .seen: return "\\Seen"
        case .flagged: return "\\Flagged"
        case .answered: return "\\Answered"
        case .draft: return "\\Draft"
        }
    }

    private func imapFlagToEmailFlag(_ flag: String) -> EmailFlag? {
        switch flag.lowercased() {
        case "\\seen": return .seen
        case "\\flagged": return .flagged
        case "\\answered": return .answered
        case "\\draft": return .draft
        default: return nil
        }
    }

    // MARK: - Response Parsing Helpers

    private func parseMailboxStatus(from response: TaggedResponse) -> MailboxStatus {
        var status = MailboxStatus()

        for line in response.untaggedLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("*") {
                let parts = trimmed.components(separatedBy: " ")

                // "* N EXISTS"
                if parts.count >= 3, parts[2] == "EXISTS" {
                    status.exists = Int(parts[1]) ?? 0
                }
                // "* N RECENT"
                if parts.count >= 3, parts[2] == "RECENT" {
                    status.recent = Int(parts[1]) ?? 0
                }
                // "* OK [UNSEEN N]"
                if trimmed.contains("[UNSEEN"), let range = trimmed.range(of: "UNSEEN ") {
                    let after = String(trimmed[range.upperBound...])
                    let numStr = after.components(separatedBy: "]").first ?? ""
                    status.unseen = Int(numStr)
                }
                // "* OK [UIDVALIDITY N]"
                if trimmed.contains("[UIDVALIDITY"), let range = trimmed.range(of: "UIDVALIDITY ") {
                    let after = String(trimmed[range.upperBound...])
                    let numStr = after.components(separatedBy: "]").first ?? ""
                    status.uidValidity = UInt32(numStr) ?? 0
                }
                // "* OK [UIDNEXT N]"
                if trimmed.contains("[UIDNEXT"), let range = trimmed.range(of: "UIDNEXT ") {
                    let after = String(trimmed[range.upperBound...])
                    let numStr = after.components(separatedBy: "]").first ?? ""
                    status.uidNext = UInt32(numStr)
                }
                // "* OK [HIGHESTMODSEQ N]"
                if trimmed.contains("[HIGHESTMODSEQ"), let range = trimmed.range(of: "HIGHESTMODSEQ ") {
                    let after = String(trimmed[range.upperBound...])
                    let numStr = after.components(separatedBy: "]").first ?? ""
                    status.highestModSeq = UInt64(numStr)
                }
            }
        }

        // Also check the tagged OK line itself for response codes.
        let taggedText = response.text
        if taggedText.contains("[UIDVALIDITY"), let range = taggedText.range(of: "UIDVALIDITY ") {
            let after = String(taggedText[range.upperBound...])
            let numStr = after.components(separatedBy: "]").first ?? ""
            if let val = UInt32(numStr) {
                status.uidValidity = val
            }
        }

        return status
    }

    /// Parse FETCH response lines into message summaries.
    private func parseFetchSummaries(from lines: [String]) -> [IMAPMessageSummary] {
        var summaries: [IMAPMessageSummary] = []

        // Each fetch response may span multiple untagged lines.
        // Look for "* N FETCH (...)" patterns.
        var currentFetchData = ""
        var inFetch = false
        var parenDepth = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if !inFetch {
                if trimmed.hasPrefix("*") && trimmed.contains("FETCH") {
                    inFetch = true
                    currentFetchData = trimmed
                    parenDepth = countParens(trimmed)
                    if parenDepth <= 0 {
                        // Complete fetch response on one line.
                        if let summary = parseSingleFetchResponse(currentFetchData) {
                            summaries.append(summary)
                        }
                        inFetch = false
                        currentFetchData = ""
                    }
                }
            } else {
                currentFetchData += " " + trimmed
                parenDepth += countParens(trimmed)
                if parenDepth <= 0 {
                    if let summary = parseSingleFetchResponse(currentFetchData) {
                        summaries.append(summary)
                    }
                    inFetch = false
                    currentFetchData = ""
                }
            }
        }

        return summaries
    }

    /// Count net open parentheses in a string (ignoring quoted content).
    private func countParens(_ s: String) -> Int {
        var depth = 0
        var inQuote = false
        for ch in s {
            if ch == "\"" { inQuote.toggle(); continue }
            if inQuote { continue }
            if ch == "(" { depth += 1 }
            else if ch == ")" { depth -= 1 }
        }
        return depth
    }

    /// Parse a single "* N FETCH (...)" response.
    private func parseSingleFetchResponse(_ line: String) -> IMAPMessageSummary? {
        // Extract UID.
        var uid: UInt32 = 0
        if let uidRange = line.range(of: "UID ", options: .caseInsensitive) {
            let after = String(line[uidRange.upperBound...])
            var digits = ""
            for ch in after {
                if ch.isNumber { digits.append(ch) } else { break }
            }
            uid = UInt32(digits) ?? 0
        }

        guard uid > 0 else { return nil }

        // Extract FLAGS.
        var flags = Set<EmailFlag>()
        if let flagsContent = extractParenContent(from: line, after: "FLAGS") {
            let parts = flagsContent.components(separatedBy: " ")
            for part in parts {
                if let f = imapFlagToEmailFlag(part) {
                    flags.insert(f)
                }
            }
        }

        // Extract RFC822.SIZE.
        var size: Int?
        if let sizeRange = line.range(of: "RFC822.SIZE ", options: .caseInsensitive) {
            let after = String(line[sizeRange.upperBound...])
            var digits = ""
            for ch in after {
                if ch.isNumber { digits.append(ch) } else { break }
            }
            size = Int(digits)
        }

        // Extract ENVELOPE and parse.
        let envelope = parseEnvelope(from: line)

        // Determine if there are attachments from BODYSTRUCTURE.
        let hasAttachments = line.uppercased().contains("ATTACHMENT")

        // Extract raw BODYSTRUCTURE.
        let bodyStructureRaw = extractParenContent(from: line, after: "BODYSTRUCTURE")

        return IMAPMessageSummary(
            uid: uid,
            flags: flags,
            envelope: envelope,
            size: size,
            hasAttachments: hasAttachments,
            bodyStructureRaw: bodyStructureRaw
        )
    }

    /// Extract the content between parentheses following a keyword.
    private func extractParenContent(from line: String, after keyword: String) -> String? {
        guard let keyRange = line.range(of: keyword, options: .caseInsensitive) else { return nil }
        let afterKey = line[keyRange.upperBound...]
        // Find the opening paren.
        guard let openParen = afterKey.firstIndex(of: "(") else { return nil }
        var depth = 0
        var idx = openParen
        while idx < afterKey.endIndex {
            let ch = afterKey[idx]
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                depth -= 1
                if depth == 0 {
                    let start = afterKey.index(after: openParen)
                    return String(afterKey[start..<idx])
                }
            }
            idx = afterKey.index(after: idx)
        }
        return nil
    }

    /// Parse the ENVELOPE portion of a FETCH response into an IMAPEnvelope.
    private func parseEnvelope(from line: String) -> IMAPEnvelope {
        guard let envelopeContent = extractParenContent(from: line, after: "ENVELOPE") else {
            return IMAPEnvelope()
        }

        let tokens = tokenizeIMAPList(envelopeContent)
        // ENVELOPE structure:
        // (date subject from sender reply-to to cc bcc in-reply-to message-id)
        // Each address field is a parenthesized list of address tuples, or NIL.

        var envelope = IMAPEnvelope()

        if tokens.count > 0 { envelope.date = parseIMAPDate(tokens[0]) }
        if tokens.count > 1 { envelope.subject = decodeIMAPString(tokens[1]) }
        if tokens.count > 2 { envelope.from = parseAddressList(tokens[2]) }
        // tokens[3] = sender, tokens[4] = reply-to (skip for now)
        if tokens.count > 5 { envelope.to = parseAddressList(tokens[5]) }
        if tokens.count > 6 { envelope.cc = parseAddressList(tokens[6]) }
        if tokens.count > 7 { envelope.bcc = parseAddressList(tokens[7]) }
        if tokens.count > 8 { envelope.inReplyTo = decodeIMAPString(tokens[8]) }
        if tokens.count > 9 { envelope.messageId = decodeIMAPString(tokens[9]) }

        return envelope
    }

    /// Tokenize an IMAP parenthesized list at the top level.
    /// Returns tokens separated by spaces, respecting quoted strings and nested parens.
    private func tokenizeIMAPList(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        var prevChar: Character?

        for ch in s {
            if ch == "\"" && prevChar != "\\" {
                inQuote.toggle()
                current.append(ch)
            } else if inQuote {
                current.append(ch)
            } else if ch == "(" {
                if depth > 0 {
                    current.append(ch)
                }
                depth += 1
            } else if ch == ")" {
                depth -= 1
                if depth > 0 {
                    current.append(ch)
                } else if depth == 0 {
                    // End of a parenthesized group.
                    tokens.append(current)
                    current = ""
                }
            } else if ch == " " && depth <= 1 {
                if !current.isEmpty || depth == 0 {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
            prevChar = ch
        }
        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    /// Parse an IMAP address list "(addr1)(addr2)..." or NIL.
    private func parseAddressList(_ s: String) -> [EmailAddress] {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.uppercased() == "NIL" || trimmed.isEmpty {
            return []
        }

        var addresses: [EmailAddress] = []
        // Split into individual address tuples.
        let tuples = extractNestedParens(trimmed)
        for tuple in tuples {
            // Address tuple: (name route mailbox host)
            let parts = tokenizeIMAPList(tuple)
            if parts.count >= 4 {
                let name = decodeIMAPString(parts[0])
                let mailbox = decodeIMAPString(parts[2]) ?? ""
                let host = decodeIMAPString(parts[3]) ?? ""
                let email = "\(mailbox)@\(host)"
                addresses.append(EmailAddress(name: name, email: email))
            }
        }
        return addresses
    }

    /// Extract nested parenthesized groups from a string.
    private func extractNestedParens(_ s: String) -> [String] {
        var groups: [String] = []
        var depth = 0
        var current = ""

        for ch in s {
            if ch == "(" {
                depth += 1
                if depth > 1 { current.append(ch) }
            } else if ch == ")" {
                depth -= 1
                if depth >= 1 {
                    current.append(ch)
                } else if depth == 0 {
                    groups.append(current)
                    current = ""
                }
            } else if depth >= 1 {
                current.append(ch)
            }
        }

        return groups
    }

    /// Decode an IMAP string value. Returns nil for "NIL".
    private func decodeIMAPString(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.uppercased() == "NIL" { return nil }
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return trimmed
    }

    /// Parse a date string from an IMAP ENVELOPE.
    private func parseIMAPDate(_ s: String) -> Date? {
        let cleaned = (decodeIMAPString(s) ?? s).trimmingCharacters(in: .whitespaces)
        if cleaned.uppercased() == "NIL" || cleaned.isEmpty { return nil }

        // Try common IMAP/RFC 2822 date formats.
        let formats: [String] = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss z",
            "dd MMM yyyy HH:mm:ss z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
        ]

        for format in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = format
            if let date = df.date(from: cleaned) {
                return date
            }
        }
        return nil
    }
}

// MARK: - MIME Parser

/// Lightweight MIME parser for extracting structured content from raw email data.
public enum MIMEParser: Sendable {

    /// Parse raw RFC 2822 header text into a dictionary.
    public static func parseHeaders(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentKey: String?
        var currentValue: String = ""

        let lines = text.components(separatedBy: "\n").map { line -> String in
            // Normalize \r\n to \n line endings.
            if line.hasSuffix("\r") {
                return String(line.dropLast())
            }
            return line
        }

        for line in lines {
            if line.isEmpty { break } // End of headers.

            // Continuation line (starts with whitespace).
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if currentKey != nil {
                    currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                }
                continue
            }

            // Save previous header.
            if let key = currentKey {
                headers[key] = currentValue
            }

            // Parse new header.
            if let colonIdx = line.firstIndex(of: ":") {
                currentKey = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                currentValue = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                currentKey = nil
            }
        }

        // Save last header.
        if let key = currentKey {
            headers[key] = currentValue
        }

        return headers
    }

    /// Split raw MIME data into headers and body.
    public static func splitHeadersAndBody(_ data: Data) -> (headers: [String: String], body: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return ([:], data)
        }

        // Find the blank line separating headers from body.
        if let range = text.range(of: "\r\n\r\n") {
            let headerText = String(text[text.startIndex..<range.lowerBound])
            let bodyText = String(text[range.upperBound...])
            return (parseHeaders(headerText), Data(bodyText.utf8))
        } else if let range = text.range(of: "\n\n") {
            let headerText = String(text[text.startIndex..<range.lowerBound])
            let bodyText = String(text[range.upperBound...])
            return (parseHeaders(headerText), Data(bodyText.utf8))
        }

        return (parseHeaders(text), Data())
    }

    /// Parse Content-Type header into (type, parameters) e.g. ("text/plain", ["charset": "utf-8"]).
    public static func parseContentType(_ value: String) -> (type: String, parameters: [String: String]) {
        let parts = value.components(separatedBy: ";")
        let type = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        var params: [String: String] = [:]

        for part in parts.dropFirst() {
            let kv = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
                var val = kv.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                if val.hasPrefix("\"") && val.hasSuffix("\"") {
                    val = String(val.dropFirst().dropLast())
                }
                params[key] = val
            }
        }

        return (type, params)
    }

    /// Parse Content-Disposition header into (disposition, parameters).
    public static func parseContentDisposition(_ value: String) -> (disposition: String, parameters: [String: String]) {
        let parts = value.components(separatedBy: ";")
        let disposition = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        var params: [String: String] = [:]

        for part in parts.dropFirst() {
            let kv = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
                var val = kv.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
                if val.hasPrefix("\"") && val.hasSuffix("\"") {
                    val = String(val.dropFirst().dropLast())
                }
                params[key] = val
            }
        }

        return (disposition, params)
    }

    /// A single MIME part extracted from a multipart message.
    public struct MIMEPart: Sendable, Equatable {
        public var headers: [String: String]
        public var contentType: String
        public var charset: String?
        public var transferEncoding: String?
        public var disposition: String?
        public var filename: String?
        public var body: Data

        public init(
            headers: [String: String] = [:],
            contentType: String = "text/plain",
            charset: String? = nil,
            transferEncoding: String? = nil,
            disposition: String? = nil,
            filename: String? = nil,
            body: Data = Data()
        ) {
            self.headers = headers
            self.contentType = contentType
            self.charset = charset
            self.transferEncoding = transferEncoding
            self.disposition = disposition
            self.filename = filename
            self.body = body
        }

        /// Decoded body text (applies transfer-encoding decoding + charset).
        public var decodedText: String? {
            let decoded: Data
            switch (transferEncoding ?? "").lowercased() {
            case "base64":
                let cleaned = String(data: body, encoding: .ascii)?
                    .replacingOccurrences(of: "\r\n", with: "")
                    .replacingOccurrences(of: "\n", with: "") ?? ""
                decoded = Data(base64Encoded: cleaned) ?? body
            case "quoted-printable":
                decoded = MIMEParser.decodeQuotedPrintable(body)
            default:
                decoded = body
            }

            let cs = (self.charset ?? "utf-8").lowercased()
            return String(data: decoded, encoding: charsetToEncoding(cs))
        }

        private func charsetToEncoding(_ charset: String) -> String.Encoding {
            switch charset {
            case "utf-8", "utf8": return .utf8
            case "iso-8859-1", "latin1": return .isoLatin1
            case "iso-8859-2": return .isoLatin2
            case "ascii", "us-ascii": return .ascii
            case "windows-1252", "cp1252": return .windowsCP1252
            case "windows-1251", "cp1251": return .windowsCP1251
            default: return .utf8
            }
        }
    }

    /// Decode quoted-printable encoded data.
    public static func decodeQuotedPrintable(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .ascii) else { return data }
        var result = Data()

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "=" {
                let next1 = text.index(after: i)
                if next1 < text.endIndex {
                    // Soft line break.
                    if text[next1] == "\r" || text[next1] == "\n" {
                        // Skip =\r\n or =\n.
                        i = text.index(after: next1)
                        if i < text.endIndex && text[i] == "\n" && text[next1] == "\r" {
                            i = text.index(after: i)
                        }
                        continue
                    }
                    let next2 = text.index(after: next1)
                    if next2 < text.endIndex {
                        let hex = String(text[next1...next2])
                        if let byte = UInt8(hex, radix: 16) {
                            result.append(byte)
                            i = text.index(after: next2)
                            continue
                        }
                    }
                }
                result.append(contentsOf: "=".utf8)
                i = text.index(after: i)
            } else {
                result.append(contentsOf: String(ch).utf8)
                i = text.index(after: i)
            }
        }

        return result
    }

    /// Parse a raw MIME message into its component parts.
    /// For non-multipart messages, returns a single part.
    public static func parseMIME(_ data: Data) -> [MIMEPart] {
        let (headers, body) = splitHeadersAndBody(data)
        let contentTypeHeader = headers["Content-Type"] ?? headers["content-type"] ?? "text/plain"
        let (contentType, ctParams) = parseContentType(contentTypeHeader)

        if contentType.hasPrefix("multipart/") {
            guard let boundary = ctParams["boundary"] else {
                // No boundary found; treat as single part.
                return [makePart(headers: headers, body: body)]
            }
            return parseMultipart(body: body, boundary: boundary)
        }

        return [makePart(headers: headers, body: body)]
    }

    /// Parse multipart body using the given boundary.
    private static func parseMultipart(body: Data, boundary: String) -> [MIMEPart] {
        guard let text = String(data: body, encoding: .utf8) else { return [] }

        let delimiter = "--" + boundary

        var parts: [MIMEPart] = []
        let sections = text.components(separatedBy: delimiter)

        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "--" { continue }
            // Skip the preamble (before first boundary) and epilogue (after closing boundary).
            if trimmed.hasPrefix("--") && trimmed.count <= 2 { continue }

            var sectionText = section
            // Strip leading line break after boundary.
            if sectionText.hasPrefix("\r\n") {
                sectionText = String(sectionText.dropFirst(2))
            } else if sectionText.hasPrefix("\n") {
                sectionText = String(sectionText.dropFirst(1))
            }

            // Strip trailing "--" if this is the closing boundary remainder.
            if sectionText.hasSuffix("--\r\n") || sectionText.hasSuffix("--\n") || sectionText.hasSuffix("--") {
                // Just use as-is; the content before the closing marker matters.
            }

            let sectionData = Data(sectionText.utf8)
            let (partHeaders, partBody) = splitHeadersAndBody(sectionData)

            let partCTHeader = partHeaders["Content-Type"] ?? partHeaders["content-type"] ?? "text/plain"
            let (partCT, partCTParams) = parseContentType(partCTHeader)

            // Recurse for nested multipart.
            if partCT.hasPrefix("multipart/"), let nestedBoundary = partCTParams["boundary"] {
                let nested = parseMultipart(body: partBody, boundary: nestedBoundary)
                parts.append(contentsOf: nested)
            } else {
                parts.append(makePart(headers: partHeaders, body: partBody))
            }
        }

        return parts
    }

    /// Create a MIMEPart from headers and raw body data.
    private static func makePart(headers: [String: String], body: Data) -> MIMEPart {
        let ctHeader = headers["Content-Type"] ?? headers["content-type"] ?? "text/plain"
        let (contentType, ctParams) = parseContentType(ctHeader)
        let charset = ctParams["charset"]

        let transferEncoding = (headers["Content-Transfer-Encoding"]
            ?? headers["content-transfer-encoding"])?.trimmingCharacters(in: .whitespaces)

        let dispHeader = headers["Content-Disposition"] ?? headers["content-disposition"]
        var disposition: String?
        var filename: String?
        if let dispHeader = dispHeader {
            let (disp, dispParams) = parseContentDisposition(dispHeader)
            disposition = disp
            filename = dispParams["filename"]
        }
        // Also check Content-Type name parameter for filename.
        if filename == nil {
            filename = ctParams["name"]
        }

        return MIMEPart(
            headers: headers,
            contentType: contentType,
            charset: charset,
            transferEncoding: transferEncoding,
            disposition: disposition,
            filename: filename,
            body: body
        )
    }

    /// Extract plain text and HTML parts from parsed MIME parts.
    public static func extractTextParts(_ parts: [MIMEPart]) -> (plain: String?, html: String?) {
        var plain: String?
        var html: String?

        for part in parts {
            if part.contentType == "text/plain" && plain == nil {
                plain = part.decodedText
            } else if part.contentType == "text/html" && html == nil {
                html = part.decodedText
            }
        }

        return (plain, html)
    }

    /// Extract attachment metadata from MIME parts (non-text parts or those with attachment disposition).
    public static func extractAttachments(_ parts: [MIMEPart]) -> [EmailAttachment] {
        var attachments: [EmailAttachment] = []
        var sectionIndex = 1

        for part in parts {
            let isAttachment = part.disposition == "attachment"
                || (part.filename != nil && part.contentType != "text/plain" && part.contentType != "text/html")
                || (!part.contentType.hasPrefix("text/") && !part.contentType.hasPrefix("multipart/"))

            if isAttachment {
                let attachment = EmailAttachment(
                    filename: part.filename ?? "attachment_\(sectionIndex)",
                    mimeType: part.contentType,
                    size: part.body.count,
                    section: "\(sectionIndex)"
                )
                attachments.append(attachment)
            }
            sectionIndex += 1
        }

        return attachments
    }
}
