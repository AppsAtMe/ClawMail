import Foundation

public struct DomainFilter: Sendable {
    public init() {}

    public func checkRecipients(_ recipients: [EmailAddress], config: GuardrailConfig) -> Result<Void, ClawMailError> {
        // Allowlist takes precedence if configured
        if let allowlist = config.domainAllowlist, !allowlist.isEmpty {
            let allowedDomains = Set(allowlist.map { $0.lowercased() })
            for recipient in recipients {
                let domain = recipient.domain.lowercased()
                if !allowedDomains.contains(domain) {
                    return .failure(.domainBlocked(domain))
                }
            }
            return .success(())
        }

        // Check blocklist
        if let blocklist = config.domainBlocklist, !blocklist.isEmpty {
            let blockedDomains = Set(blocklist.map { $0.lowercased() })
            for recipient in recipients {
                let domain = recipient.domain.lowercased()
                if blockedDomains.contains(domain) {
                    return .failure(.domainBlocked(domain))
                }
            }
        }

        return .success(())
    }
}
