import Foundation
import NIO
import NIOSSL

// MARK: - OutgoingEmail

public struct OutgoingEmail: Sendable {
    public var from: EmailAddress
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    public var bodyPlain: String
    public var bodyHtml: String?
    public var attachments: [OutgoingAttachment]
    public var inReplyTo: String?
    public var references: String?
    public var customHeaders: [String: String]

    public init(
        from: EmailAddress,
        to: [EmailAddress],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String,
        bodyPlain: String,
        bodyHtml: String? = nil,
        attachments: [OutgoingAttachment] = [],
        inReplyTo: String? = nil,
        references: String? = nil,
        customHeaders: [String: String] = [:]
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyPlain = bodyPlain
        self.bodyHtml = bodyHtml
        self.attachments = attachments
        self.inReplyTo = inReplyTo
        self.references = references
        self.customHeaders = customHeaders
    }
}

// MARK: - OutgoingAttachment

public struct OutgoingAttachment: Sendable {
    public var data: Data
    public var filename: String
    public var mimeType: String

    public init(data: Data, filename: String, mimeType: String) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }

    public static func fromFile(path: String) throws -> OutgoingAttachment {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent
        let mimeType = Self.guessMIMEType(for: url.pathExtension)
        return OutgoingAttachment(data: data, filename: filename, mimeType: mimeType)
    }

    private static func guessMIMEType(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "gz", "gzip": return "application/gzip"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "txt": return "text/plain"
        case "html", "htm": return "text/html"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - SMTPClient

public actor SMTPClient {
    private let host: String
    private let port: Int
    private let security: ConnectionSecurity
    private let credentials: Credentials
    private let senderEmail: String

    private var group: EventLoopGroup?
    private var channel: Channel?
    private let responseQueue = SMTPResponseQueue()

    public init(host: String, port: Int, security: ConnectionSecurity, credentials: Credentials, senderEmail: String) {
        self.host = host
        self.port = port
        self.security = security
        self.credentials = credentials
        self.senderEmail = senderEmail
    }

    // MARK: - Connection

    public func connect() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let queue: SMTPResponseQueue = responseQueue
        let smtpHost: String = host

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)

        let channel = try await bootstrap.connect(host: smtpHost, port: port).get()
        self.channel = channel

        // Add handlers after connection
        if security == .ssl {
            let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: smtpHost)
            try await channel.pipeline.addHandler(sslHandler).get()
        }
        try await channel.pipeline.addHandler(ByteToMessageHandler(SMTPLineHandler())).get()
        try await channel.pipeline.addHandler(SMTPResponseHandler(queue: queue)).get()

        // Read server greeting
        let greeting = try await readResponse()
        guard greeting.code == 220 else {
            throw ClawMailError.connectionError("SMTP server rejected connection: \(greeting.message)")
        }

        // EHLO
        try await sendCommand("EHLO clawmail.local")
        let ehloResponse = try await readResponse()
        guard ehloResponse.code == 250 else {
            throw ClawMailError.connectionError("EHLO failed: \(ehloResponse.message)")
        }

        // STARTTLS if needed
        if security == .starttls {
            try await sendCommand("STARTTLS")
            let starttlsResponse = try await readResponse()
            guard starttlsResponse.code == 220 else {
                throw ClawMailError.connectionError("STARTTLS failed: \(starttlsResponse.message)")
            }
            let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
            try await channel.pipeline.addHandler(sslHandler).get()

            // Re-EHLO after STARTTLS
            try await sendCommand("EHLO clawmail.local")
            let _ = try await readResponse()
        }

        // Authenticate
        try await authenticate()
    }

    private func authenticate() async throws {
        switch credentials {
        case .password(let password):
            // Try AUTH PLAIN first
            let authString = "\0\(senderEmail)\0\(password)"
            let encoded = Data(authString.utf8).base64EncodedString()
            try await sendCommand("AUTH PLAIN \(encoded)")
            let response = try await readResponse()
            guard response.code == 235 else {
                throw ClawMailError.authFailed("SMTP AUTH PLAIN failed: \(response.message)")
            }

        case .oauth2(let accessToken, _, _):
            let authString = "user=\(senderEmail)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
            let encoded = Data(authString.utf8).base64EncodedString()
            try await sendCommand("AUTH XOAUTH2 \(encoded)")
            let response = try await readResponse()
            guard response.code == 235 else {
                throw ClawMailError.authFailed("SMTP XOAUTH2 failed: \(response.message)")
            }
        }
    }

    // MARK: - Send

    public func send(message: OutgoingEmail) async throws -> String {
        let messageId = generateMessageId(domain: message.from.domain)
        let mimeData = buildMIME(message: message, messageId: messageId)

        // MAIL FROM — sanitize email to prevent SMTP command injection
        try await sendCommand("MAIL FROM:<\(sanitizeHeaderValue(message.from.email))>")
        let fromResponse = try await readResponse()
        guard fromResponse.code == 250 else {
            throw ClawMailError.connectionError("MAIL FROM rejected: \(fromResponse.message)")
        }

        // RCPT TO for all recipients — sanitize each address
        let allRecipients = message.to + message.cc + message.bcc
        for recipient in allRecipients {
            try await sendCommand("RCPT TO:<\(sanitizeHeaderValue(recipient.email))>")
            let rcptResponse = try await readResponse()
            guard rcptResponse.code == 250 else {
                throw ClawMailError.connectionError("RCPT TO rejected for \(recipient.email): \(rcptResponse.message)")
            }
        }

        // DATA
        try await sendCommand("DATA")
        let dataResponse = try await readResponse()
        guard dataResponse.code == 354 else {
            throw ClawMailError.connectionError("DATA rejected: \(dataResponse.message)")
        }

        // Send message body followed by lone dot
        try await sendRawData(mimeData)
        try await sendCommand("\r\n.")
        let sentResponse = try await readResponse()
        guard sentResponse.code == 250 else {
            throw ClawMailError.connectionError("Message rejected: \(sentResponse.message)")
        }

        return messageId
    }

    public func disconnect() async throws {
        if channel?.isActive == true {
            try await sendCommand("QUIT")
            _ = try? await readResponse()
            try await channel?.close()
        }
        try await group?.shutdownGracefully()
        channel = nil
        group = nil
    }

    // MARK: - MIME Construction

    /// Strip CR and LF to prevent SMTP header injection.
    private func sanitizeHeaderValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private func buildMIME(message: OutgoingEmail, messageId: String) -> String {
        let boundary = "ClawMail-\(UUID().uuidString)"
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        var headers: [String] = []
        headers.append("Message-ID: <\(sanitizeHeaderValue(messageId))>")
        headers.append("Date: \(dateFmt.string(from: Date()))")
        headers.append("From: \(sanitizeHeaderValue(message.from.displayString))")
        headers.append("To: \(message.to.map { sanitizeHeaderValue($0.displayString) }.joined(separator: ", "))")
        if !message.cc.isEmpty {
            headers.append("Cc: \(message.cc.map { sanitizeHeaderValue($0.displayString) }.joined(separator: ", "))")
        }
        headers.append("Subject: \(encodeHeader(message.subject))")
        headers.append("MIME-Version: 1.0")

        if let inReplyTo = message.inReplyTo {
            headers.append("In-Reply-To: <\(sanitizeHeaderValue(inReplyTo))>")
        }
        if let references = message.references {
            headers.append("References: \(sanitizeHeaderValue(references))")
        }
        for (key, value) in message.customHeaders {
            let safeKey = sanitizeHeaderValue(key)
            let safeValue = sanitizeHeaderValue(value)
            // Also reject keys containing ":" to prevent header name spoofing
            guard !safeKey.contains(":") else { continue }
            headers.append("\(safeKey): \(safeValue)")
        }

        var body: String

        if !message.attachments.isEmpty {
            // multipart/mixed
            headers.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
            body = "\r\n"

            if let html = message.bodyHtml {
                let altBoundary = "ClawMail-alt-\(UUID().uuidString)"
                body += "--\(boundary)\r\n"
                body += "Content-Type: multipart/alternative; boundary=\"\(altBoundary)\"\r\n\r\n"
                body += "--\(altBoundary)\r\n"
                body += "Content-Type: text/plain; charset=utf-8\r\n"
                body += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
                body += quotedPrintableEncode(message.bodyPlain) + "\r\n"
                body += "--\(altBoundary)\r\n"
                body += "Content-Type: text/html; charset=utf-8\r\n"
                body += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
                body += quotedPrintableEncode(html) + "\r\n"
                body += "--\(altBoundary)--\r\n"
            } else {
                body += "--\(boundary)\r\n"
                body += "Content-Type: text/plain; charset=utf-8\r\n"
                body += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
                body += quotedPrintableEncode(message.bodyPlain) + "\r\n"
            }

            for attachment in message.attachments {
                let safeName = sanitizeHeaderValue(attachment.filename)
                    .replacingOccurrences(of: "\"", with: "'")
                let safeMime = sanitizeHeaderValue(attachment.mimeType)
                body += "--\(boundary)\r\n"
                body += "Content-Type: \(safeMime); name=\"\(safeName)\"\r\n"
                body += "Content-Disposition: attachment; filename=\"\(safeName)\"\r\n"
                body += "Content-Transfer-Encoding: base64\r\n\r\n"
                body += attachment.data.base64EncodedString(options: .lineLength76Characters) + "\r\n"
            }
            body += "--\(boundary)--\r\n"

        } else if let html = message.bodyHtml {
            // multipart/alternative
            headers.append("Content-Type: multipart/alternative; boundary=\"\(boundary)\"")
            body = "\r\n"
            body += "--\(boundary)\r\n"
            body += "Content-Type: text/plain; charset=utf-8\r\n"
            body += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
            body += quotedPrintableEncode(message.bodyPlain) + "\r\n"
            body += "--\(boundary)\r\n"
            body += "Content-Type: text/html; charset=utf-8\r\n"
            body += "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
            body += quotedPrintableEncode(html) + "\r\n"
            body += "--\(boundary)--\r\n"

        } else {
            // Simple text
            headers.append("Content-Type: text/plain; charset=utf-8")
            headers.append("Content-Transfer-Encoding: quoted-printable")
            body = "\r\n" + quotedPrintableEncode(message.bodyPlain)
        }

        return headers.joined(separator: "\r\n") + "\r\n" + body
    }

    private func generateMessageId(domain: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = UUID().uuidString.prefix(8)
        let host = domain.isEmpty ? "clawmail.local" : domain
        return "\(timestamp).\(random)@\(host)"
    }

    private func encodeHeader(_ value: String) -> String {
        // Always strip CRLF first to prevent header injection, even for ASCII values
        let safe = sanitizeHeaderValue(value)
        // RFC 2047 encoding for non-ASCII
        if safe.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return safe
        }
        let encoded = Data(safe.utf8).base64EncodedString()
        return "=?UTF-8?B?\(encoded)?="
    }

    private func quotedPrintableEncode(_ text: String) -> String {
        var result = ""
        var lineLength = 0

        for byte in text.utf8 {
            let char = Character(UnicodeScalar(byte))
            if (byte >= 33 && byte <= 126 && byte != 61) || char == " " || char == "\t" {
                if char == "\r" || char == "\n" {
                    result.append(char)
                    lineLength = 0
                    continue
                }
                if lineLength >= 75 {
                    result += "=\r\n"
                    lineLength = 0
                }
                result.append(char)
                lineLength += 1
            } else if byte == 13 || byte == 10 {
                result.append(char)
                lineLength = 0
            } else {
                let encoded = String(format: "=%02X", byte)
                if lineLength + 3 >= 76 {
                    result += "=\r\n"
                    lineLength = 0
                }
                result += encoded
                lineLength += 3
            }
        }

        return result
    }

    // MARK: - Low-level I/O

    private func sendCommand(_ command: String) async throws {
        guard let channel = channel else {
            throw ClawMailError.connectionError("Not connected to SMTP server")
        }
        var buffer = channel.allocator.buffer(capacity: command.utf8.count + 2)
        buffer.writeString(command + "\r\n")
        try await channel.writeAndFlush(buffer)
    }

    private func sendRawData(_ data: String) async throws {
        guard let channel = channel else {
            throw ClawMailError.connectionError("Not connected to SMTP server")
        }
        // Dot-stuffing per RFC 5321: lines beginning with "." get an extra "." prepended
        var stuffed = data.replacingOccurrences(of: "\r\n.", with: "\r\n..")
        if stuffed.hasPrefix(".") {
            stuffed = "." + stuffed
        }
        var buffer = channel.allocator.buffer(capacity: stuffed.utf8.count)
        buffer.writeString(stuffed)
        try await channel.writeAndFlush(buffer)
    }

    private func readResponse() async throws -> SMTPResponse {
        guard channel != nil else {
            throw ClawMailError.connectionError("Not connected to SMTP server")
        }
        return await responseQueue.getNextResponse()
    }
}

// MARK: - SMTP Types

struct SMTPResponse: Sendable {
    let code: Int
    let message: String
}

// MARK: - Response Queue (actor-based for Swift 6 safety)

actor SMTPResponseQueue {
    private var responses: [SMTPResponse] = []
    private var waiters: [CheckedContinuation<SMTPResponse, Never>] = []

    func enqueue(_ response: SMTPResponse) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: response)
        } else {
            responses.append(response)
        }
    }

    func getNextResponse() async -> SMTPResponse {
        if let response = responses.first {
            responses.removeFirst()
            return response
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

// MARK: - NIO Handlers

private final class SMTPLineHandler: ByteToMessageDecoder, Sendable {
    typealias InboundOut = String

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let crlfIndex = buffer.readableBytesView.firstIndex(of: UInt8(ascii: "\n")) else {
            return .needMoreData
        }
        let length = crlfIndex - buffer.readableBytesView.startIndex
        guard var line = buffer.readString(length: length) else {
            return .needMoreData
        }
        buffer.moveReaderIndex(forwardBy: 1) // consume the \n
        if line.hasSuffix("\r") {
            line = String(line.dropLast())
        }
        context.fireChannelRead(wrapInboundOut(line))
        return .continue
    }
}

private final class SMTPResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = String

    private let queue: SMTPResponseQueue

    init(queue: SMTPResponseQueue) {
        self.queue = queue
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let line = unwrapInboundIn(data)

        if line.count >= 3, let code = Int(line.prefix(3)) {
            let message = line.count > 4 ? String(line.dropFirst(4)) : ""
            // Multi-line continuation: 4th char is "-"
            if line.count > 3 && line[line.index(line.startIndex, offsetBy: 3)] == "-" {
                return
            }
            let response = SMTPResponse(code: code, message: message)
            Task { await self.queue.enqueue(response) }
        }
    }
}
