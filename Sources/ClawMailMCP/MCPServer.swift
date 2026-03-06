import Foundation
import ClawMailCore

// MARK: - Entry Point

@main
struct MCPServerMain {
    static func main() async {
        let server = MCPServer()
        await server.run()
    }
}

// MARK: - Stdout Writer

/// Serializes writes to stdout to prevent interleaving from concurrent tasks.
/// In Swift 6 strict concurrency, an actor is the correct way to serialize access.
actor StdoutWriter {
    private let handle = FileHandle.standardOutput

    /// Write a JSON-RPC response to stdout as a single newline-delimited line.
    func write(_ response: JSONRPCResponse) {
        do {
            let data = try encodeJSONRPC(response)
            handle.write(data)
        } catch {
            MCPServer.log("Failed to encode response: \(error)")
        }
    }

    /// Write a JSON-RPC notification to stdout.
    func write(_ notification: JSONRPCNotification) {
        do {
            let data = try encodeJSONRPC(notification)
            handle.write(data)
        } catch {
            MCPServer.log("Failed to encode notification: \(error)")
        }
    }
}

// MARK: - MCP Server

/// MCP (Model Context Protocol) stdio server for ClawMail.
///
/// Reads JSON-RPC 2.0 from stdin and writes responses to stdout.
/// Connects to the running ClawMail daemon via Unix domain socket IPC.
final class MCPServer: Sendable {

    static let protocolVersion = "2024-11-05"
    static let serverName = "clawmail"
    static let serverVersion = "1.0.0"

    private let ipcClient: IPCClient
    private let writer: StdoutWriter
    private let toolDispatcher: MCPToolDispatcher
    private let resourceHandler: MCPResourceHandler

    init() {
        let client = IPCClient(sessionType: .agent)
        self.ipcClient = client
        self.writer = StdoutWriter()
        self.toolDispatcher = MCPToolDispatcher(ipcClient: client)
        self.resourceHandler = MCPResourceHandler(ipcClient: client)
    }

    /// Log a message to stderr (never to stdout, which is reserved for JSON-RPC).
    static func log(_ message: String) {
        let line = "[ClawMailMCP] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    // MARK: - Run Loop

    /// Main run loop. Connects to daemon, then reads stdin line-by-line.
    func run() async {
        Self.log("ClawMail MCP server starting...")

        // Connect to daemon
        do {
            try await ipcClient.connect()
            Self.log("Connected to ClawMail daemon")
        } catch {
            Self.log("Warning: Could not connect to daemon: \(error). Will attempt on first request.")
        }

        // Forward IPC notifications to MCP stdout with clawmail/ prefix
        ipcClient.onNotification = { [writer] notification in
            Task {
                let mcpNotification = NotificationForwarder.forwardToMCP(notification)
                await writer.write(mcpNotification)
            }
        }

        // Read lines from stdin
        Self.log("Listening on stdin...")
        await readStdin()

        // Cleanup
        await ipcClient.disconnect()
        Self.log("MCP server shutting down.")
    }

    /// Read stdin line-by-line using a buffered approach compatible with Swift 6 concurrency.
    private func readStdin() async {
        // Use FileHandle bytes for async line reading
        let stdinHandle = FileHandle.standardInput
        var buffer = Data()

        while true {
            let chunk = stdinHandle.availableData
            if chunk.isEmpty {
                // EOF — stdin closed
                Self.log("stdin closed (EOF)")
                break
            }

            buffer.append(chunk)

            // Process all complete lines in the buffer
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                if lineData.isEmpty { continue }

                await processLine(Data(lineData))
            }
        }
    }

    // MARK: - Message Processing

    /// Process a single line of JSON-RPC input.
    private func processLine(_ data: Data) async {
        // First, try to decode as a request (has "id" and "method")
        if let request = try? decodeJSONRPC(JSONRPCRequest.self, from: data) {
            await handleRequest(request)
            return
        }

        // Try to decode as a notification (has "method" but no "id")
        if let notification = try? decodeJSONRPC(JSONRPCNotification.self, from: data) {
            await handleNotification(notification)
            return
        }

        // Could not parse — send a parse error response
        Self.log("Failed to parse JSON-RPC message")
        let errorResponse = JSONRPCResponse.error(
            id: nil,
            code: JSONRPCError.parseError,
            message: "Parse error: could not decode JSON-RPC message"
        )
        await writer.write(errorResponse)
    }

    // MARK: - Request Handling

    /// Handle a JSON-RPC request (expects a response).
    private func handleRequest(_ request: JSONRPCRequest) async {
        Self.log("Request: \(request.method) [id=\(request.id)]")

        switch request.method {
        case "initialize":
            await handleInitialize(request)
        case "ping":
            await handlePing(request)
        case "tools/list":
            await handleToolsList(request)
        case "tools/call":
            await handleToolsCall(request)
        case "resources/list":
            await handleResourcesList(request)
        case "resources/read":
            await handleResourcesRead(request)
        case "resources/templates/list":
            await handleResourceTemplatesList(request)
        default:
            Self.log("Unknown method: \(request.method)")
            let response = JSONRPCResponse.error(
                id: request.id,
                code: JSONRPCError.methodNotFound,
                message: "Method not found: \(request.method)"
            )
            await writer.write(response)
        }
    }

    /// Handle a JSON-RPC notification (no response expected).
    private func handleNotification(_ notification: JSONRPCNotification) async {
        Self.log("Notification: \(notification.method)")

        switch notification.method {
        case "initialized", "notifications/initialized":
            Self.log("Client initialized — MCP session active")
        case "notifications/cancelled":
            Self.log("Client cancelled a request")
        default:
            Self.log("Unhandled notification: \(notification.method)")
        }
    }

    // MARK: - MCP Protocol Handlers

    /// Handle `initialize` — respond with server capabilities.
    private func handleInitialize(_ request: JSONRPCRequest) async {
        let result: AnyCodableValue = .dictionary([
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .dictionary([
                "tools": .dictionary([:]),
                "resources": .dictionary([:]),
            ]),
            "serverInfo": .dictionary([
                "name": .string(Self.serverName),
                "version": .string(Self.serverVersion),
            ]),
        ])
        let response = JSONRPCResponse.success(id: request.id, result: result)
        await writer.write(response)
    }

    /// Handle `ping` — respond with empty result.
    private func handlePing(_ request: JSONRPCRequest) async {
        let response = JSONRPCResponse.success(id: request.id, result: .dictionary([:]))
        await writer.write(response)
    }

    /// Handle `tools/list` — return all tool definitions.
    private func handleToolsList(_ request: JSONRPCRequest) async {
        let toolValues = MCPTools.all.map { $0.toMCPValue() }
        let result: AnyCodableValue = .dictionary([
            "tools": .array(toolValues),
        ])
        let response = JSONRPCResponse.success(id: request.id, result: result)
        await writer.write(response)
    }

    /// Handle `tools/call` — dispatch to IPC and return result.
    private func handleToolsCall(_ request: JSONRPCRequest) async {
        guard let params = request.params,
              case .string(let toolName) = params["name"] else {
            let response = JSONRPCResponse.error(
                id: request.id,
                code: JSONRPCError.invalidParams,
                message: "Missing required parameter 'name' in tools/call"
            )
            await writer.write(response)
            return
        }

        // Extract arguments — they may be nested under "arguments" key
        let arguments: [String: AnyCodableValue]?
        if case .dictionary(let args) = params["arguments"] {
            arguments = args
        } else {
            arguments = nil
        }

        Self.log("Tool call: \(toolName)")

        // Ensure IPC connection
        if !ipcClient.isConnected {
            do {
                try await ipcClient.connect()
            } catch {
                let errorResult: AnyCodableValue = .dictionary([
                    "isError": .bool(true),
                    "content": .array([
                        .dictionary([
                            "type": .string("text"),
                            "text": .string("Error: ClawMail daemon is not running. Start ClawMail.app first."),
                        ])
                    ]),
                ])
                let response = JSONRPCResponse.success(id: request.id, result: errorResult)
                await writer.write(response)
                return
            }
        }

        let callResult = await toolDispatcher.dispatch(name: toolName, arguments: arguments)
        let response = JSONRPCResponse.success(id: request.id, result: callResult.toMCPResult())
        await writer.write(response)
    }

    /// Handle `resources/list` — return all resource definitions.
    private func handleResourcesList(_ request: JSONRPCRequest) async {
        let resourceValues = MCPResourceRegistry.resources.map { $0.toMCPValue() }
        let result: AnyCodableValue = .dictionary([
            "resources": .array(resourceValues),
        ])
        let response = JSONRPCResponse.success(id: request.id, result: result)
        await writer.write(response)
    }

    /// Handle `resources/templates/list` — return all resource template definitions.
    private func handleResourceTemplatesList(_ request: JSONRPCRequest) async {
        let templateValues = MCPResourceRegistry.resourceTemplates.map { $0.toMCPValue() }
        let result: AnyCodableValue = .dictionary([
            "resourceTemplates": .array(templateValues),
        ])
        let response = JSONRPCResponse.success(id: request.id, result: result)
        await writer.write(response)
    }

    /// Handle `resources/read` — fetch resource data via IPC.
    private func handleResourcesRead(_ request: JSONRPCRequest) async {
        guard let params = request.params,
              case .string(let uri) = params["uri"] else {
            let response = JSONRPCResponse.error(
                id: request.id,
                code: JSONRPCError.invalidParams,
                message: "Missing required parameter 'uri' in resources/read"
            )
            await writer.write(response)
            return
        }

        Self.log("Resource read: \(uri)")

        // Ensure IPC connection
        if !ipcClient.isConnected {
            do {
                try await ipcClient.connect()
            } catch {
                let errorResult: AnyCodableValue = .dictionary([
                    "contents": .array([
                        .dictionary([
                            "uri": .string(uri),
                            "mimeType": .string("text/plain"),
                            "text": .string("Error: ClawMail daemon is not running. Start ClawMail.app first."),
                        ])
                    ]),
                ])
                let response = JSONRPCResponse.success(id: request.id, result: errorResult)
                await writer.write(response)
                return
            }
        }

        let result = await resourceHandler.read(uri: uri)
        let response = JSONRPCResponse.success(id: request.id, result: result)
        await writer.write(response)
    }
}
