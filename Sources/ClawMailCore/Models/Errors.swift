import Foundation

// MARK: - ClawMailError

public enum ClawMailError: Error, LocalizedError, Codable, Sendable {
    case accountNotFound(String)
    case accountDisconnected(String)
    case authFailed(String)
    case messageNotFound(String)
    case folderNotFound(String)
    case rateLimitExceeded(retryAfterSeconds: Int)
    case domainBlocked(String)
    case recipientPendingApproval(emails: [String])
    case agentAlreadyConnected
    case connectionError(String)
    case invalidParameter(String)
    case serverError(String)
    case calendarNotAvailable
    case contactsNotAvailable
    case tasksNotAvailable
    case daemonNotRunning

    public var code: String {
        switch self {
        case .accountNotFound: return "ACCOUNT_NOT_FOUND"
        case .accountDisconnected: return "ACCOUNT_DISCONNECTED"
        case .authFailed: return "AUTH_FAILED"
        case .messageNotFound: return "MESSAGE_NOT_FOUND"
        case .folderNotFound: return "FOLDER_NOT_FOUND"
        case .rateLimitExceeded: return "RATE_LIMIT_EXCEEDED"
        case .domainBlocked: return "DOMAIN_BLOCKED"
        case .recipientPendingApproval: return "RECIPIENT_PENDING_APPROVAL"
        case .agentAlreadyConnected: return "AGENT_ALREADY_CONNECTED"
        case .connectionError: return "CONNECTION_ERROR"
        case .invalidParameter: return "INVALID_PARAMETER"
        case .serverError: return "SERVER_ERROR"
        case .calendarNotAvailable: return "CALENDAR_NOT_AVAILABLE"
        case .contactsNotAvailable: return "CONTACTS_NOT_AVAILABLE"
        case .tasksNotAvailable: return "TASKS_NOT_AVAILABLE"
        case .daemonNotRunning: return "DAEMON_NOT_RUNNING"
        }
    }

    public var errorDescription: String? { message }

    public var message: String {
        switch self {
        case .accountNotFound(let label):
            return "Account '\(label)' not found"
        case .accountDisconnected(let label):
            return "Account '\(label)' is not connected to the server"
        case .authFailed(let reason):
            return "Authentication failed: \(reason)"
        case .messageNotFound(let id):
            return "Message '\(id)' not found"
        case .folderNotFound(let name):
            return "Folder '\(name)' not found"
        case .rateLimitExceeded(let seconds):
            return "Send rate limit exceeded. Try again in \(seconds) seconds."
        case .domainBlocked(let domain):
            return "Recipient domain '\(domain)' is not allowed"
        case .recipientPendingApproval(let emails):
            return "First-time recipients pending approval: \(emails.joined(separator: ", "))"
        case .agentAlreadyConnected:
            return "Another agent session is already active"
        case .connectionError(let msg):
            return "Connection error: \(msg)"
        case .invalidParameter(let msg):
            return "Invalid parameter: \(msg)"
        case .serverError(let msg):
            return "Server error: \(msg)"
        case .calendarNotAvailable:
            return "CalDAV is not configured for this account"
        case .contactsNotAvailable:
            return "CardDAV is not configured for this account"
        case .tasksNotAvailable:
            return "Tasks (CalDAV VTODO) not configured for this account"
        case .daemonNotRunning:
            return "ClawMail daemon is not running. Start ClawMail.app first."
        }
    }
}

// MARK: - ErrorResponse

public struct ErrorResponse: Codable, Sendable {
    public var error: ErrorDetail

    public struct ErrorDetail: Codable, Sendable {
        public var code: String
        public var message: String
        public var details: [String: AnyCodableValue]?
    }

    public init(from clawError: ClawMailError) {
        var details: [String: AnyCodableValue]? = nil
        if case .rateLimitExceeded(let seconds) = clawError {
            details = [
                "retry_after_seconds": .int(seconds),
            ]
        }
        self.error = ErrorDetail(code: clawError.code, message: clawError.message, details: details)
    }

    public func toJSON() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return (try? encoder.encode(self)) ?? Data()
    }

    public func toJSONString() -> String {
        String(data: toJSON(), encoding: .utf8) ?? "{}"
    }
}
