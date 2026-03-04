import Foundation
import ClawMailCore

// MARK: - MCP Tool Dispatcher

/// Dispatches MCP tool calls to the ClawMail daemon via IPC.
///
/// Maps MCP tool names (e.g., `email_list`) to IPC method names (e.g., `email.list`)
/// and forwards arguments. Results are formatted as MCP tool result content arrays.
actor MCPToolDispatcher {

    private let ipcClient: IPCClient

    init(ipcClient: IPCClient) {
        self.ipcClient = ipcClient
    }

    // MARK: - Tool Call Result

    /// The result of an MCP tool call, ready to be embedded in a JSON-RPC response.
    struct ToolCallResult: Sendable {
        let content: AnyCodableValue
        let isError: Bool

        /// Produce the MCP `result` dictionary for a `tools/call` response.
        func toMCPResult() -> AnyCodableValue {
            var dict: [String: AnyCodableValue] = [
                "content": content,
            ]
            if isError {
                dict["isError"] = .bool(true)
            }
            return .dictionary(dict)
        }
    }

    // MARK: - Dispatch

    /// Execute a tool call by name with the given arguments.
    ///
    /// - Parameters:
    ///   - name: The MCP tool name (e.g., `email_list`).
    ///   - arguments: The arguments dictionary from the MCP request.
    /// - Returns: A `ToolCallResult` containing content for the MCP response.
    func dispatch(name: String, arguments: [String: AnyCodableValue]?) async -> ToolCallResult {
        guard let toolDef = MCPTools.byName[name] else {
            return ToolCallResult(
                content: .array([
                    .dictionary([
                        "type": .string("text"),
                        "text": .string("Error: Unknown tool '\(name)'"),
                    ])
                ]),
                isError: true
            )
        }

        do {
            let result = try await ipcClient.call(method: toolDef.ipcMethod, params: arguments)
            let resultText = resultToJSONString(result)
            return ToolCallResult(
                content: .array([
                    .dictionary([
                        "type": .string("text"),
                        "text": .string(resultText),
                    ])
                ]),
                isError: false
            )
        } catch {
            let errorMessage: String
            if let clawError = error as? ClawMailError {
                errorMessage = "Error: \(clawError.message)"
            } else {
                errorMessage = "Error: \(error.localizedDescription)"
            }
            return ToolCallResult(
                content: .array([
                    .dictionary([
                        "type": .string("text"),
                        "text": .string(errorMessage),
                    ])
                ]),
                isError: true
            )
        }
    }

    // MARK: - JSON Serialization

    /// Convert an `AnyCodableValue` result to a pretty-printed JSON string.
    private func resultToJSONString(_ value: AnyCodableValue) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "\(value)"
        }
    }
}
