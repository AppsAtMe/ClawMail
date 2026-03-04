import Foundation

public actor RateLimiter {
    private let auditLog: AuditLog

    public init(auditLog: AuditLog) {
        self.auditLog = auditLog
    }

    public func checkSendAllowed(account: String, config: RateLimitConfig) throws -> Result<Void, ClawMailError> {
        let now = Date()

        // Check per-minute limit
        if let maxPerMinute = config.maxPerMinute {
            let since = now.addingTimeInterval(-60)
            let count = try auditLog.countSends(account: account, since: since)
            if count >= maxPerMinute {
                return .failure(.rateLimitExceeded(retryAfterSeconds: 60))
            }
        }

        // Check per-hour limit
        if let maxPerHour = config.maxPerHour {
            let since = now.addingTimeInterval(-3600)
            let count = try auditLog.countSends(account: account, since: since)
            if count >= maxPerHour {
                let secondsUntilReset = 3600 - Int(now.timeIntervalSince(since))
                return .failure(.rateLimitExceeded(retryAfterSeconds: max(secondsUntilReset, 60)))
            }
        }

        // Check per-day limit
        if let maxPerDay = config.maxPerDay {
            let since = now.addingTimeInterval(-86400)
            let count = try auditLog.countSends(account: account, since: since)
            if count >= maxPerDay {
                let secondsUntilReset = 86400 - Int(now.timeIntervalSince(since))
                return .failure(.rateLimitExceeded(retryAfterSeconds: max(secondsUntilReset, 60)))
            }
        }

        return .success(())
    }
}
