import Foundation

// MARK: - AgentInterface

public enum AgentInterface: String, Codable, Sendable {
    case mcp
    case cli
    case rest
}

// MARK: - AuditEntry

public struct AuditEntry: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var timestamp: Date
    public var interface: AgentInterface
    public var operation: String
    public var account: String?
    public var parameters: [String: AnyCodableValue]?
    public var result: AuditResult
    public var details: [String: AnyCodableValue]?

    public init(
        id: Int64? = nil,
        timestamp: Date = Date(),
        interface: AgentInterface,
        operation: String,
        account: String? = nil,
        parameters: [String: AnyCodableValue]? = nil,
        result: AuditResult,
        details: [String: AnyCodableValue]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.interface = interface
        self.operation = operation
        self.account = account
        self.parameters = parameters
        self.result = result
        self.details = details
    }
}

// MARK: - AuditResult

public enum AuditResult: String, Codable, Sendable {
    case success
    case failure
}

// MARK: - AnyCodableValue (for flexible JSON parameters/details)

public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(value)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public static func from(_ value: Any) -> AnyCodableValue {
        switch value {
        case let v as String: return .string(v)
        case let v as Int: return .int(v)
        case let v as Double: return .double(v)
        case let v as Bool: return .bool(v)
        case let v as [Any]: return .array(v.map { from($0) })
        case let v as [String: Any]: return .dictionary(v.mapValues { from($0) })
        default: return .null
        }
    }
}
