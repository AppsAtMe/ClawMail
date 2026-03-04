import Foundation

// MARK: - JSON-RPC 2.0 Types

/// JSON-RPC 2.0 request object.
public struct JSONRPCRequest: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var id: JSONRPCId
    public var method: String
    public var params: [String: AnyCodableValue]?

    public init(id: JSONRPCId, method: String, params: [String: AnyCodableValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response object.
public struct JSONRPCResponse: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var id: JSONRPCId?
    public var result: AnyCodableValue?
    public var error: JSONRPCError?

    public init(id: JSONRPCId?, result: AnyCodableValue) {
        self.id = id
        self.result = result
    }

    public init(id: JSONRPCId?, error: JSONRPCError) {
        self.id = id
        self.error = error
    }

    public static func success(id: JSONRPCId, result: AnyCodableValue) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: result)
    }

    public static func error(id: JSONRPCId?, code: Int, message: String, data: AnyCodableValue? = nil) -> JSONRPCResponse {
        JSONRPCResponse(id: id, error: JSONRPCError(code: code, message: message, data: data))
    }
}

/// JSON-RPC 2.0 notification (no id, no response expected).
public struct JSONRPCNotification: Codable, Sendable {
    public var jsonrpc: String = "2.0"
    public var method: String
    public var params: [String: AnyCodableValue]?

    public init(method: String, params: [String: AnyCodableValue]? = nil) {
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 error object.
public struct JSONRPCError: Codable, Sendable {
    public var code: Int
    public var message: String
    public var data: AnyCodableValue?

    public init(code: Int, message: String, data: AnyCodableValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC 2.0 error codes
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    // Application-specific error codes (using -32000..-32099 range)
    public static let accountNotFound = -32001
    public static let messageNotFound = -32002
    public static let authFailed = -32003
    public static let rateLimited = -32004
    public static let domainBlocked = -32005
    public static let pendingApproval = -32006
    public static let agentAlreadyConnected = -32007
    public static let serviceNotAvailable = -32008
    public static let daemonNotRunning = -32009

    /// Create a JSONRPCError from a ClawMailError.
    public static func from(_ error: ClawMailError) -> JSONRPCError {
        switch error {
        case .accountNotFound(let label):
            return JSONRPCError(code: accountNotFound, message: error.message, data: .string(label))
        case .messageNotFound(let id):
            return JSONRPCError(code: messageNotFound, message: error.message, data: .string(id))
        case .authFailed:
            return JSONRPCError(code: authFailed, message: error.message)
        case .rateLimitExceeded(let seconds):
            return JSONRPCError(code: rateLimited, message: error.message, data: .int(seconds))
        case .domainBlocked(let domain):
            return JSONRPCError(code: domainBlocked, message: error.message, data: .string(domain))
        case .recipientPendingApproval(let emails):
            return JSONRPCError(code: pendingApproval, message: error.message,
                                data: .array(emails.map { .string($0) }))
        case .agentAlreadyConnected:
            return JSONRPCError(code: agentAlreadyConnected, message: error.message)
        case .calendarNotAvailable, .contactsNotAvailable, .tasksNotAvailable:
            return JSONRPCError(code: serviceNotAvailable, message: error.message)
        case .daemonNotRunning:
            return JSONRPCError(code: daemonNotRunning, message: error.message)
        default:
            return JSONRPCError(code: internalError, message: error.message)
        }
    }
}

/// JSON-RPC 2.0 id can be string, number, or null.
public enum JSONRPCId: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCId.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

// MARK: - Message framing helpers

/// Encode a Codable value to newline-delimited JSON Data.
public func encodeJSONRPC<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var data = try encoder.encode(value)
    data.append(contentsOf: [0x0A]) // newline delimiter
    return data
}

/// Decode a JSON-RPC message from Data (expecting a single JSON line).
public func decodeJSONRPC<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: data)
}
