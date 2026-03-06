import Foundation

// MARK: - GuardrailResult

public enum GuardrailResult: Sendable {
    case allowed
    case blocked(ClawMailError)
    case pendingApproval(emails: [String])
}

// MARK: - GuardrailEngine

public actor GuardrailEngine {
    private let config: () -> GuardrailConfig
    private let rateLimiter: RateLimiter
    private let domainFilter: DomainFilter
    private let metadataIndex: MetadataIndex

    public init(config: @escaping @Sendable () -> GuardrailConfig, auditLog: AuditLog, metadataIndex: MetadataIndex) {
        self.config = config
        self.rateLimiter = RateLimiter(auditLog: auditLog)
        self.domainFilter = DomainFilter()
        self.metadataIndex = metadataIndex
    }

    /// Check if an email send operation is allowed
    public func checkSend(account: String, recipients: [EmailAddress]) async throws -> GuardrailResult {
        let guardrailConfig = config()

        // 1. Check rate limits
        if let rateLimit = guardrailConfig.sendRateLimit {
            let result = try await rateLimiter.checkSendAllowed(account: account, config: rateLimit)
            if case .failure(let error) = result {
                return .blocked(error)
            }
        }

        // 2. Check domain filters
        let domainResult = domainFilter.checkRecipients(recipients, config: guardrailConfig)
        if case .failure(let error) = domainResult {
            return .blocked(error)
        }

        // 3. Check first-time recipient approval
        if guardrailConfig.firstTimeRecipientApproval {
            var needsApproval: [String] = []
            for recipient in recipients {
                let approved = try metadataIndex.isRecipientApproved(email: recipient.email, account: account)
                if !approved {
                    needsApproval.append(recipient.email)
                }
            }
            if !needsApproval.isEmpty {
                return .pendingApproval(emails: needsApproval)
            }
        }

        return .allowed
    }

    /// Check for non-send write operations (calendar, contacts, tasks) — currently no guardrails
    public func checkWrite(operation: String, account: String) -> GuardrailResult {
        .allowed
    }
}
