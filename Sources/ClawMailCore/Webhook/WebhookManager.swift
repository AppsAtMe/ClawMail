import Foundation

// MARK: - WebhookManager

/// Sends webhook notifications (e.g., on new email) to a configured URL.
/// Retries with exponential backoff on failure (max 3 retries).
public actor WebhookManager {

    private let webhookURL: URL
    private let session: URLSession
    private let maxRetries: Int
    private let baseDelay: UInt64 // nanoseconds

    public init?(urlString: String?, maxRetries: Int = 3, baseDelayNanoseconds: UInt64 = 1_000_000_000) {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return nil
        }
        // Only allow http/https schemes to prevent SSRF via file://, ftp://, etc.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        // Block requests to cloud metadata endpoints and loopback addresses.
        let blockedHosts = [
            "169.254.169.254",          // AWS/GCP/Azure IMDS
            "metadata.google.internal", // GCP metadata
            "::1",                      // IPv6 loopback (URL.host strips brackets)
            "[::1]",                    // IPv6 loopback (with brackets)
            "127.0.0.1",                // IPv4 loopback
            "localhost",                // loopback hostname
            "0.0.0.0",                  // wildcard (routes to localhost on some stacks)
        ]
        if let host = url.host?.lowercased(), blockedHosts.contains(host) {
            return nil
        }
        self.webhookURL = url
        self.maxRetries = maxRetries
        self.baseDelay = baseDelayNanoseconds

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    /// The validated URL this manager posts to.
    public var url: URL { webhookURL }

    // MARK: - Notifications

    /// Send a new-email webhook notification.
    public func notifyNewEmail(account: String, folder: String) async {
        let payload = WebhookPayload(
            event: "new_email",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            data: [
                "account": account,
                "folder": folder,
            ]
        )
        await sendWithRetry(payload: payload)
    }

    /// Send a generic webhook notification.
    public func notify(event: String, data: [String: String]) async {
        let payload = WebhookPayload(
            event: event,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            data: data
        )
        await sendWithRetry(payload: payload)
    }

    // MARK: - Internal

    private func sendWithRetry(payload: WebhookPayload) async {
        var lastError: (any Error)?

        for attempt in 0..<maxRetries {
            do {
                try await send(payload: payload)
                return // Success
            } catch {
                lastError = error
                // Exponential backoff: 1x, 2x, 4x base delay
                let delay = UInt64(pow(2.0, Double(attempt))) * baseDelay
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        // All retries exhausted — log to stderr
        if let error = lastError {
            fputs("WebhookManager: Failed to deliver webhook to \(webhookURL) after \(maxRetries) attempts: \(String(describing: error))\n", stderr)
        }
    }

    private func send(payload: WebhookPayload) async throws {
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ClawMail/1.0", forHTTPHeaderField: "User-Agent")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebhookError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WebhookError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Types

public struct WebhookPayload: Codable, Sendable {
    public var event: String
    public var timestamp: String
    public var data: [String: String]

    public init(event: String, timestamp: String, data: [String: String]) {
        self.event = event
        self.timestamp = timestamp
        self.data = data
    }
}

public enum WebhookError: Error, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
}
