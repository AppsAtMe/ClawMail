import Foundation

public enum DAVURLValidator {
    public static func validateOptionalURLString(
        _ rawValue: String,
        serviceName: String
    ) throws -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed) else {
            throw ClawMailError.invalidParameter("\(serviceName) URL is invalid")
        }
        return try validateConfiguredURL(url, serviceName: serviceName)
    }

    public static func validateConfiguredURL(_ url: URL, serviceName: String) throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw ClawMailError.invalidParameter("\(serviceName) URL must use HTTPS")
        }
        guard let host = url.host, !host.isEmpty else {
            throw ClawMailError.invalidParameter("\(serviceName) URL must include a host")
        }
        return url
    }

    static func resolveServerURL(
        _ path: String,
        relativeTo baseURL: URL,
        serviceName: String,
        context: String
    ) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClawMailError.serverError("\(serviceName) \(context): Server returned an empty URL")
        }

        if let candidate = URL(string: trimmed), let scheme = candidate.scheme?.lowercased() {
            guard scheme == "https" else {
                throw ClawMailError.serverError("\(serviceName) \(context): Server returned a non-HTTPS URL")
            }
            guard isTrustedOrigin(candidate, relativeTo: baseURL, serviceName: serviceName) else {
                let candidateHost = candidate.host?.lowercased() ?? "unknown"
                let baseHost = baseURL.host?.lowercased() ?? "unknown"
                throw ClawMailError.serverError(
                    "\(serviceName) \(context): Server returned a cross-origin URL (\(candidateHost) relative to \(baseHost))"
                )
            }
            return candidate
        }

        if trimmed.hasPrefix("/") {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw ClawMailError.serverError("\(serviceName) \(context): Failed to resolve URL components")
            }
            components.path = trimmed
            components.query = nil
            components.fragment = nil
            guard let resolved = components.url else {
                throw ClawMailError.serverError("\(serviceName) \(context): Failed to build URL")
            }
            return resolved
        }

        return baseURL.appendingPathComponent(trimmed)
    }

    private static func isTrustedOrigin(_ candidate: URL, relativeTo baseURL: URL, serviceName: String) -> Bool {
        if hasSameOrigin(candidate, as: baseURL) {
            return true
        }
        return isTrustedAppleDAVShardHost(candidate, relativeTo: baseURL, serviceName: serviceName)
    }

    private static func hasSameOrigin(_ candidate: URL, as baseURL: URL) -> Bool {
        candidate.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && candidate.host?.lowercased() == baseURL.host?.lowercased()
            && effectivePort(for: candidate) == effectivePort(for: baseURL)
    }

    private static func isTrustedAppleDAVShardHost(
        _ candidate: URL,
        relativeTo baseURL: URL,
        serviceName: String
    ) -> Bool {
        guard let family = appleDAVFamily(for: serviceName) else {
            return false
        }
        guard effectivePort(for: candidate) == effectivePort(for: baseURL),
              candidate.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              let candidateHost = candidate.host?.lowercased(),
              let baseHost = baseURL.host?.lowercased() else {
            return false
        }

        return family.contains(candidateHost) && family.contains(baseHost)
    }

    private static func appleDAVFamily(for serviceName: String) -> AppleDAVFamily? {
        switch serviceName {
        case "CalDAV":
            return AppleDAVFamily(
                canonicalHosts: ["caldav.icloud.com"],
                shardLabels: ["caldav", "caldavws", "calendarws"]
            )
        case "CardDAV":
            return AppleDAVFamily(
                canonicalHosts: ["contacts.icloud.com"],
                shardLabels: ["contacts", "contactsws", "carddav", "carddavws"]
            )
        default:
            return nil
        }
    }

    private struct AppleDAVFamily {
        let canonicalHosts: Set<String>
        let shardLabels: Set<String>

        func contains(_ host: String) -> Bool {
            canonicalHosts.contains(host) || Self.isShardHost(host, allowedLabels: shardLabels)
        }

        private static func isShardHost(_ host: String, allowedLabels: Set<String>) -> Bool {
            let suffix = ".icloud.com"
            guard host.hasSuffix(suffix) else { return false }

            let prefix = String(host.dropLast(suffix.count))
            let components = prefix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { return false }

            let partition = components[0]
            guard partition.first == "p" else { return false }

            let partitionDigits = partition.dropFirst()
            guard !partitionDigits.isEmpty, partitionDigits.allSatisfy(\.isNumber) else {
                return false
            }

            return allowedLabels.contains(String(components[1]))
        }
    }

    private static func effectivePort(for url: URL) -> Int? {
        if let port = url.port {
            return port
        }

        switch url.scheme?.lowercased() {
        case "https":
            return 443
        case "http":
            return 80
        default:
            return nil
        }
    }
}
