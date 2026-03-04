import Foundation
import ClawMailCore

// MARK: - WebhookManager

/// Sends webhook notifications (e.g., on new email) to a configured URL.
/// Retries with exponential backoff on failure (max 3 retries).
public actor WebhookManager {

    private let webhookURL: URL
    private let session: URLSession
    private let maxRetries = 3

    public init?(urlString: String?) {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return nil
        }
        // Only allow http/https schemes to prevent SSRF via file://, ftp://, etc.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        // Block requests to cloud metadata endpoints and loopback
        let blockedHosts = ["169.254.169.254", "metadata.google.internal", "[::1]"]
        if let host = url.host?.lowercased(), blockedHosts.contains(host) {
            return nil
        }
        self.webhookURL = url

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

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
                // Exponential backoff: 1s, 2s, 4s
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        // All retries exhausted — log to stderr
        if let error = lastError {
            fputs("WebhookManager: Failed to deliver webhook to \(webhookURL) after \(maxRetries) attempts: \(error.localizedDescription)\n", stderr)
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

struct WebhookPayload: Codable, Sendable {
    var event: String
    var timestamp: String
    var data: [String: String]
}

enum WebhookError: Error, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
}
