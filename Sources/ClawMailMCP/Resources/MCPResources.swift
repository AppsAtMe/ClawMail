import Foundation
import ClawMailCore

// MARK: - MCP Resource Definition

/// Represents an MCP resource exposed by the server.
struct MCPResourceDefinition: Sendable {
    let uri: String
    let name: String
    let description: String
    let mimeType: String

    /// Convert to MCP wire format.
    func toMCPValue() -> AnyCodableValue {
        .dictionary([
            "uri": .string(uri),
            "name": .string(name),
            "description": .string(description),
            "mimeType": .string(mimeType),
        ])
    }
}

// MARK: - MCP Resource Template Definition

/// Represents an MCP resource template (parameterized URI).
struct MCPResourceTemplateDefinition: Sendable {
    let uriTemplate: String
    let name: String
    let description: String
    let mimeType: String

    /// Convert to MCP wire format.
    func toMCPValue() -> AnyCodableValue {
        .dictionary([
            "uriTemplate": .string(uriTemplate),
            "name": .string(name),
            "description": .string(description),
            "mimeType": .string(mimeType),
        ])
    }
}

// MARK: - Resource Registry

/// Registry of all MCP resources and resource templates.
enum MCPResourceRegistry {

    /// Static (non-parameterized) resources.
    static let resources: [MCPResourceDefinition] = [
        MCPResourceDefinition(
            uri: "clawmail://accounts",
            name: "Account List",
            description: "List all configured email accounts and their connection status",
            mimeType: "application/json"
        ),
    ]

    /// Parameterized resource templates.
    static let resourceTemplates: [MCPResourceTemplateDefinition] = [
        MCPResourceTemplateDefinition(
            uriTemplate: "clawmail://accounts/{label}/status",
            name: "Account Status",
            description: "Connection and sync status for a specific account",
            mimeType: "application/json"
        ),
        MCPResourceTemplateDefinition(
            uriTemplate: "clawmail://accounts/{label}/folders",
            name: "Account Folders",
            description: "List all email folders for a specific account",
            mimeType: "application/json"
        ),
    ]
}

// MARK: - Resource Handler

/// Handles MCP `resources/read` requests by fetching data via IPC.
actor MCPResourceHandler {

    private let ipcClient: IPCClient

    init(ipcClient: IPCClient) {
        self.ipcClient = ipcClient
    }

    /// Read a resource by URI.
    ///
    /// - Parameter uri: The resource URI (e.g., `clawmail://accounts`).
    /// - Returns: The MCP `result` value for a `resources/read` response.
    func read(uri: String) async -> AnyCodableValue {
        do {
            let content = try await fetchResource(uri: uri)
            return .dictionary([
                "contents": .array([
                    .dictionary([
                        "uri": .string(uri),
                        "mimeType": .string("application/json"),
                        "text": .string(content),
                    ])
                ])
            ])
        } catch {
            let errorMessage: String
            if let clawError = error as? ClawMailError {
                errorMessage = clawError.message
            } else {
                errorMessage = error.localizedDescription
            }
            return .dictionary([
                "contents": .array([
                    .dictionary([
                        "uri": .string(uri),
                        "mimeType": .string("text/plain"),
                        "text": .string("Error: \(errorMessage)"),
                    ])
                ])
            ])
        }
    }

    // MARK: - URI Routing

    /// Route a resource URI to the appropriate IPC call.
    private func fetchResource(uri: String) async throws -> String {
        // Parse URI: clawmail://accounts, clawmail://accounts/{label}/status, etc.
        guard uri.hasPrefix("clawmail://") else {
            throw ClawMailError.invalidParameter("Invalid resource URI: \(uri)")
        }

        let path = String(uri.dropFirst("clawmail://".count))
        let components = path.split(separator: "/").map(String.init)

        switch components.count {
        case 1 where components[0] == "accounts":
            // clawmail://accounts -> list all accounts
            let result = try await ipcClient.call(method: "accounts.list")
            return try encodeResultAsJSON(result)

        case 2 where components[0] == "accounts":
            // This would be clawmail://accounts/{label} — not defined, treat as status
            let label = components[1]
            let result = try await ipcClient.call(method: "status", params: ["account": .string(label)])
            return try encodeResultAsJSON(result)

        case 3 where components[0] == "accounts" && components[2] == "status":
            // clawmail://accounts/{label}/status
            let label = components[1]
            let result = try await ipcClient.call(method: "status", params: ["account": .string(label)])
            return try encodeResultAsJSON(result)

        case 3 where components[0] == "accounts" && components[2] == "folders":
            // clawmail://accounts/{label}/folders
            let label = components[1]
            let result = try await ipcClient.call(method: "email.listFolders", params: ["account": .string(label)])
            return try encodeResultAsJSON(result)

        default:
            throw ClawMailError.invalidParameter("Unknown resource URI: \(uri)")
        }
    }

    /// Encode an `AnyCodableValue` to a pretty-printed JSON string.
    private func encodeResultAsJSON(_ value: AnyCodableValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
