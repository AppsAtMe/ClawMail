import Foundation
import Hummingbird

// MARK: - AuthMiddleware

/// Hummingbird middleware that validates API key authentication via Bearer token.
///
/// Extracts `Authorization: Bearer <key>` from request headers and compares
/// against the configured API key. Skips authentication for health check endpoint.
struct AuthMiddleware: RouterMiddleware {
    typealias Context = BasicRequestContext

    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
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
        guard token == apiKey else {
            return unauthorizedResponse(message: "Invalid API key")
        }

        return try await next(request, context)
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
