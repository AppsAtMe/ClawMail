import Foundation
import Hummingbird
import HTTPTypes

/// HTTP-level rate limiting middleware using a token bucket algorithm.
///
/// Limits the number of requests per time window to prevent abuse of
/// list/search endpoints. This is separate from the email send rate limiter
/// in GuardrailEngine, which operates at the business logic layer.
///
/// Since the REST API only binds to 127.0.0.1, all requests come from
/// localhost — we use a single global bucket rather than per-IP tracking.
struct RateLimitMiddleware: RouterMiddleware {
    typealias Context = BasicRequestContext

    private let bucket: TokenBucket

    /// Create a rate limiter.
    /// - Parameters:
    ///   - maxRequests: Maximum requests allowed per window (bucket capacity).
    ///   - windowSeconds: Time window in seconds for the bucket to fully refill.
    init(maxRequests: Int = 120, windowSeconds: Double = 60) {
        self.bucket = TokenBucket(
            capacity: maxRequests,
            refillRate: Double(maxRequests) / windowSeconds
        )
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Skip rate limiting for health check
        if request.uri.path == "/api/v1/status" && request.method == .get {
            return try await next(request, context)
        }

        guard bucket.consume() else {
            let retryAfter = Int(ceil(1.0 / bucket.refillRate))
            var headers = HTTPFields()
            headers[.contentType] = "application/json"
            headers[.retryAfter] = "\(retryAfter)"
            let body: [String: [String: String]] = [
                "error": [
                    "code": "RATE_LIMITED",
                    "message": "Too many requests. Try again in \(retryAfter) seconds.",
                ]
            ]
            let data = (try? JSONEncoder().encode(body)) ?? Data()
            return Response(
                status: .tooManyRequests,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        return try await next(request, context)
    }
}

// MARK: - Token Bucket

/// Thread-safe token bucket rate limiter.
///
/// Tokens refill continuously at `refillRate` per second up to `capacity`.
/// Each request consumes one token. When the bucket is empty, requests are rejected.
private final class TokenBucket: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    let refillRate: Double
    private var tokens: Double
    private var lastRefill: CFAbsoluteTime

    init(capacity: Int, refillRate: Double) {
        self.capacity = capacity
        self.refillRate = refillRate
        self.tokens = Double(capacity)
        self.lastRefill = CFAbsoluteTimeGetCurrent()
    }

    /// Try to consume one token. Returns true if a token was available.
    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastRefill
        lastRefill = now

        // Refill tokens based on elapsed time
        tokens = min(Double(capacity), tokens + elapsed * refillRate)

        if tokens >= 1.0 {
            tokens -= 1.0
            return true
        }
        return false
    }
}
