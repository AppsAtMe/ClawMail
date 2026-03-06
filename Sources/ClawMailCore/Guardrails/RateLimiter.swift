import Foundation

public actor RateLimiter {
    private let auditLog: AuditLog

    public init(auditLog: AuditLog) {
        self.auditLog = auditLog
    }

    public func checkSendAllowed(account: String, config: RateLimitConfig) throws -> Result<Void, ClawMailError> {
        let now = Date()

        if let maxPerMinute = config.maxPerMinute {
            let result = try checkWindow(account: account, windowSeconds: 60, limit: maxPerMinute, now: now)
            if case .failure = result { return result }
        }
        if let maxPerHour = config.maxPerHour {
            let result = try checkWindow(account: account, windowSeconds: 3600, limit: maxPerHour, now: now)
            if case .failure = result { return result }
        }
        if let maxPerDay = config.maxPerDay {
            let result = try checkWindow(account: account, windowSeconds: 86400, limit: maxPerDay, now: now)
            if case .failure = result { return result }
        }

        return .success(())
    }

    private func checkWindow(
        account: String,
        windowSeconds: TimeInterval,
        limit: Int,
        now: Date
    ) throws -> Result<Void, ClawMailError> {
        let since = now.addingTimeInterval(-windowSeconds)
        let count = try auditLog.countSends(account: account, since: since)
        guard count >= limit else { return .success(()) }
        let oldest = try auditLog.oldestSendTimestamp(account: account, since: since)
        let resetAt = (oldest ?? since).addingTimeInterval(windowSeconds)
        return .failure(.rateLimitExceeded(retryAfterSeconds: max(Int(resetAt.timeIntervalSince(now)), 60)))
    }
}
