import Foundation
import Hummingbird
import ClawMailCore

// MARK: - AuthMiddleware

/// Hummingbird middleware that validates API key authentication via Bearer token.
///
/// Reads the current API key from Keychain on each request so that key regeneration
/// takes effect immediately without restarting the server.
struct AuthMiddleware: RouterMiddleware {
    typealias Context = BasicRequestContext

    private let keychainManager: KeychainManager

    init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Skip auth for health check endpoint
        if request.uri.path == "/api/v1/status" && request.method == .get {
            return try await next(request, context)
        }

        // Extract Bearer token from Authorization header
        guard let authHeader = request.headers[.authorization] else {
            return unauthorizedResponse(message: "Missing Authorization header")
        }

        let prefix = "Bearer "
        guard authHeader.hasPrefix(prefix) else {
            return unauthorizedResponse(message: "Authorization header must use Bearer scheme")
        }

        let token = String(authHeader.dropFirst(prefix.count))

        // Read current key from Keychain (supports hot-reload after regeneration)
        guard let currentKey = await keychainManager.getAPIKey() else {
            return unauthorizedResponse(message: "API key not configured")
        }

        guard constantTimeEqual(Data(token.utf8), Data(currentKey.utf8)) else {
            return unauthorizedResponse(message: "Invalid API key")
        }

        return try await next(request, context)
    }

    /// Constant-time comparison to prevent timing attacks.
    /// Returns true only if both buffers have identical length and content.
    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }

    private func unauthorizedResponse(message: String) -> Response {
        let body: [String: [String: String]] = [
            "error": [
                "code": "AUTH_FAILED",
                "message": message,
            ]
        ]
        let data = (try? JSONEncoder().encode(body)) ?? Data()
        return Response(
            status: .unauthorized,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}
