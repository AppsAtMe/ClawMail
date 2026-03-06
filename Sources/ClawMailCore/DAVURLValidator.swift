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
            guard hasSameOrigin(candidate, as: baseURL) else {
                throw ClawMailError.serverError("\(serviceName) \(context): Server returned a cross-origin URL")
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

    private static func hasSameOrigin(_ candidate: URL, as baseURL: URL) -> Bool {
        candidate.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && candidate.host?.lowercased() == baseURL.host?.lowercased()
            && effectivePort(for: candidate) == effectivePort(for: baseURL)
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
