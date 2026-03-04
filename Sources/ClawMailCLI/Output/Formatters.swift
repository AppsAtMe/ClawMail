import Foundation
import ClawMailCore

// MARK: - OutputFormat

/// Output format for CLI commands: JSON (default, agent-friendly), text (human-readable), or CSV.
public enum OutputFormat: String, CaseIterable, Sendable, ExpressibleByArgument {
    case json
    case text
    case csv

    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}

// We need to import ArgumentParser for ExpressibleByArgument
import ArgumentParser

// MARK: - OutputFormatter

/// Formats AnyCodableValue results for CLI output.
public enum OutputFormatter {

    /// Format a result value according to the requested output format.
    public static func format(_ value: AnyCodableValue, as outputFormat: OutputFormat) -> String {
        switch outputFormat {
        case .json:
            return formatJSON(value)
        case .text:
            return formatText(value)
        case .csv:
            return formatCSV(value)
        }
    }

    // MARK: - JSON Formatting

    /// Pretty-print the value as JSON.
    public static func formatJSON(_ value: AnyCodableValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    // MARK: - Text Formatting

    /// Format the value as human-readable text.
    public static func formatText(_ value: AnyCodableValue, indent: Int = 0) -> String {
        let prefix = String(repeating: "  ", count: indent)
        switch value {
        case .string(let s):
            return s
        case .int(let i):
            return "\(i)"
        case .double(let d):
            return "\(d)"
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .array(let items):
            if items.isEmpty { return "(empty)" }
            return items.enumerated().map { index, item in
                formatArrayItem(item, index: index, indent: indent)
            }.joined(separator: "\n")
        case .dictionary(let dict):
            if dict.isEmpty { return "(empty)" }
            let maxKeyLen = dict.keys.map(\.count).max() ?? 0
            return dict.sorted(by: { $0.key < $1.key }).map { key, val in
                let paddedKey = key.padding(toLength: maxKeyLen, withPad: " ", startingAt: 0)
                let nested = isComplex(val)
                if nested {
                    return "\(prefix)\(paddedKey):\n\(formatText(val, indent: indent + 1))"
                } else {
                    return "\(prefix)\(paddedKey): \(formatText(val))"
                }
            }.joined(separator: "\n")
        }
    }

    private static func formatArrayItem(_ item: AnyCodableValue, index: Int, indent: Int) -> String {
        let prefix = String(repeating: "  ", count: indent)
        switch item {
        case .dictionary:
            let separator = index > 0 ? "\(prefix)---\n" : ""
            return separator + formatText(item, indent: indent)
        default:
            return "\(prefix)- \(formatText(item))"
        }
    }

    // MARK: - CSV Formatting

    /// Format as CSV. Works best with arrays of dictionaries (tabular data).
    public static func formatCSV(_ value: AnyCodableValue) -> String {
        guard case .array(let items) = value else {
            // Non-array: fall back to a single-value CSV
            return csvEscape(formatText(value))
        }

        // Collect all unique keys across all dictionary items for the header row
        var allKeys: [String] = []
        var keySet = Set<String>()
        for item in items {
            if case .dictionary(let dict) = item {
                for key in dict.keys.sorted() where !keySet.contains(key) {
                    allKeys.append(key)
                    keySet.insert(key)
                }
            }
        }

        guard !allKeys.isEmpty else {
            return items.map { formatText($0) }.joined(separator: "\n")
        }

        var lines: [String] = []
        lines.append(allKeys.joined(separator: ","))

        for item in items {
            if case .dictionary(let dict) = item {
                let row = allKeys.map { key in
                    csvEscape(flatValue(dict[key] ?? .null))
                }
                lines.append(row.joined(separator: ","))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func flatValue(_ value: AnyCodableValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array, .dictionary: return formatJSON(value)
        }
    }

    private static func isComplex(_ value: AnyCodableValue) -> Bool {
        switch value {
        case .dictionary, .array:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error Output

/// Format a ClawMailError as JSON for stderr output.
public func formatErrorJSON(_ error: ClawMailError) -> String {
    let response = ErrorResponse(from: error)
    return response.toJSONString()
}

/// Format a generic error as JSON for stderr output.
public func formatGenericErrorJSON(code: String, message: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let dict: [String: [String: String]] = [
        "error": [
            "code": code,
            "message": message,
        ],
    ]
    guard let data = try? encoder.encode(dict),
          let str = String(data: data, encoding: .utf8) else {
        return #"{"error":{"code":"\#(code)","message":"\#(message)"}}"#
    }
    return str
}

// MARK: - CLIError

/// Errors that can occur during CLI command execution.
enum CLIError: Error {
    case daemonNotRunning
    case serverError(String)
    case invalidInput(String)

    var exitCode: Int32 { 1 }

    func printAndExit() -> Never {
        switch self {
        case .daemonNotRunning:
            FileHandle.standardError.write(
                Data(formatErrorJSON(.daemonNotRunning).utf8)
            )
        case .serverError(let msg):
            FileHandle.standardError.write(
                Data(formatGenericErrorJSON(code: "SERVER_ERROR", message: msg).utf8)
            )
        case .invalidInput(let msg):
            FileHandle.standardError.write(
                Data(formatGenericErrorJSON(code: "INVALID_INPUT", message: msg).utf8)
            )
        }
        FileHandle.standardError.write(Data("\n".utf8))
        Foundation.exit(exitCode)
    }
}

// MARK: - Command Helper

/// Shared helper to connect to daemon, execute a call, and handle errors.
public func executeRPC(
    socketPath: String? = nil,
    method: String,
    params: [String: AnyCodableValue]? = nil,
    format: OutputFormat
) async -> Never {
    let client = IPCClient(socketPath: socketPath)
    do {
        try await client.connect()
    } catch {
        await client.disconnect()
        CLIError.daemonNotRunning.printAndExit()
    }

    do {
        let result = try await client.call(method: method, params: params)
        let output = OutputFormatter.format(result, as: format)
        print(output)
        await client.disconnect()
        Foundation.exit(0)
    } catch let error as ClawMailError {
        await client.disconnect()
        FileHandle.standardError.write(Data(formatErrorJSON(error).utf8))
        FileHandle.standardError.write(Data("\n".utf8))
        Foundation.exit(1)
    } catch {
        await client.disconnect()
        CLIError.serverError(error.localizedDescription).printAndExit()
    }
}
