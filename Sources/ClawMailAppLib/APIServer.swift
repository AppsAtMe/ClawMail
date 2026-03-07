import Foundation
import Hummingbird
import HummingbirdCore
import HTTPTypes
import NIOCore
import NIOFoundationCompat
import ClawMailCore

// MARK: - APIServer

/// Embedded REST API server using Hummingbird, bound to localhost.
/// Provides programmatic access to all ClawMail operations via HTTP/JSON.
public actor APIServer {

    private let orchestrator: AccountOrchestrator
    private let port: Int
    private var runTask: Task<Void, Never>?

    public init(orchestrator: AccountOrchestrator, port: Int = 24601, apiKey: String? = nil) {
        self.orchestrator = orchestrator
        self.port = port
    }

    // MARK: - Lifecycle

    /// Start the HTTP server on 127.0.0.1 with the configured port.
    public func start() async throws {
        guard runTask == nil else { return }

        let router = buildRouter()
        let startupSignal = ServerStartupSignal()

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: port)
            ),
            onServerRunning: { _ in
                await startupSignal.markRunning()
            }
        )

        let task = Task {
            do {
                // The menu bar app owns its own lifecycle; the embedded REST server
                // should not register process-wide signal handlers.
                try await app.runService(gracefulShutdownSignals: [])
            } catch is CancellationError {
                _ = await startupSignal.failIfWaiting(CancellationError())
            } catch {
                let startupFailed = await startupSignal.failIfWaiting(error)
                if !startupFailed {
                    Self.log("REST API server stopped unexpectedly: \(Self.describe(error))")
                }
            }
        }
        runTask = task

        do {
            try await startupSignal.waitUntilRunning()
        } catch {
            task.cancel()
            runTask = nil
            throw error
        }
    }

    /// Stop the HTTP server.
    public func stop() async {
        guard let task = runTask else { return }
        runTask = nil
        task.cancel()
        await task.value
    }

    // MARK: - Router Setup

    private func buildRouter() -> Router<BasicRequestContext> {
        let router = Router()

        // Auth middleware reads from Keychain on each request for hot-reload support.
        router.middlewares.add(RateLimitMiddleware())
        router.middlewares.add(AuthMiddleware(keychainManager: KeychainManager()))

        // Register all route groups
        StatusRoutes.register(on: router, orchestrator: orchestrator)
        EmailRoutes.register(on: router, orchestrator: orchestrator)
        CalendarRoutes.register(on: router, orchestrator: orchestrator)
        ContactsRoutes.register(on: router, orchestrator: orchestrator)
        TasksRoutes.register(on: router, orchestrator: orchestrator)
        AuditRoutes.register(on: router, orchestrator: orchestrator)
        RecipientsRoutes.register(on: router, orchestrator: orchestrator)

        return router
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[APIServer] \(message)\n".utf8))
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }
}

private actor ServerStartupSignal {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Void, any Error>)
        case running
        case failed(any Error)
    }

    private var state: State = .idle

    func waitUntilRunning() async throws {
        switch state {
        case .running:
            return
        case .failed(let error):
            throw error
        case .idle:
            try await withCheckedThrowingContinuation { continuation in
                state = .waiting(continuation)
            }
        case .waiting:
            preconditionFailure("waitUntilRunning() called more than once")
        }
    }

    func markRunning() {
        switch state {
        case .idle:
            state = .running
        case .waiting(let continuation):
            state = .running
            continuation.resume()
        case .running, .failed:
            break
        }
    }

    @discardableResult
    func failIfWaiting(_ error: any Error) -> Bool {
        switch state {
        case .idle:
            state = .failed(error)
            return true
        case .waiting(let continuation):
            state = .failed(error)
            continuation.resume(throwing: error)
            return true
        case .running:
            return false
        case .failed:
            return true
        }
    }
}

// MARK: - JSON Helpers

/// Shared JSON encoder configured for the REST API.
func apiJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

/// Shared JSON decoder configured for the REST API.
func apiJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

/// Encode a value to a Hummingbird `Response` with JSON content type.
func jsonResponse<T: Encodable & Sendable>(_ value: T, status: HTTPResponse.Status = .ok) -> Response {
    do {
        let data = try apiJSONEncoder().encode(value)
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    } catch {
        return internalErrorResponse("Failed to encode response: \(error.localizedDescription)")
    }
}

/// Build a JSON error response from a `ClawMailError`.
func clawMailErrorResponse(_ error: ClawMailError) -> Response {
    let errorResponse = ErrorResponse(from: error)
    let status = httpStatus(for: error)
    do {
        let data = try apiJSONEncoder().encode(errorResponse)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        if case .rateLimitExceeded(let seconds) = error {
            headers[.retryAfter] = "\(seconds)"
        }
        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    } catch {
        return internalErrorResponse("Failed to encode error response")
    }
}

/// Build a generic error response for non-ClawMailError errors.
func genericErrorResponse(_ error: any Error) -> Response {
    if let clawError = error as? ClawMailError {
        return clawMailErrorResponse(clawError)
    }
    return internalErrorResponse(String(describing: error))
}

/// Build a 500 Internal Server Error response.
func internalErrorResponse(_ message: String) -> Response {
    let body: [String: [String: String]] = [
        "error": [
            "code": "INTERNAL_ERROR",
            "message": message,
        ]
    ]
    let data = (try? JSONEncoder().encode(body)) ?? Data()
    return Response(
        status: .internalServerError,
        headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(data: data))
    )
}

/// Build a 400 Bad Request response for missing/invalid parameters.
func badRequestResponse(_ message: String) -> Response {
    let clawError = ClawMailError.invalidParameter(message)
    return clawMailErrorResponse(clawError)
}

/// Map ClawMailError to HTTP status codes.
func httpStatus(for error: ClawMailError) -> HTTPResponse.Status {
    switch error {
    case .accountNotFound, .messageNotFound, .folderNotFound:
        return .notFound
    case .authFailed:
        return .unauthorized
    case .rateLimitExceeded:
        return .tooManyRequests
    case .domainBlocked:
        return .forbidden
    case .recipientPendingApproval:
        return .conflict
    case .invalidParameter:
        return .badRequest
    case .daemonNotRunning:
        return .serviceUnavailable
    case .agentAlreadyConnected:
        return .conflict
    case .accountDisconnected:
        return .serviceUnavailable
    case .connectionError:
        return .badGateway
    case .calendarNotAvailable, .contactsNotAvailable, .tasksNotAvailable:
        return .notFound
    case .serverError:
        return .internalServerError
    }
}

/// Decode a JSON request body using the shared decoder.
func decodeBody<T: Decodable>(_ type: T.Type, from request: Request, context: BasicRequestContext) async throws -> T {
    let body = try await request.body.collect(upTo: 10 * 1024 * 1024) // 10 MB max
    return try apiJSONDecoder().decode(type, from: body)
}

// MARK: - Query Parameter Helpers

/// Maximum allowed length for string query parameters (4 KB).
private let maxQueryParamLength = 4096

/// Maximum allowed limit for paginated queries.
private let maxResultLimit = 500

/// Get a required query parameter or throw ClawMailError.invalidParameter.
func requireQueryParam(_ params: Parameters, _ name: String) throws -> String {
    guard let value = params.get(name) else {
        throw ClawMailError.invalidParameter("Missing required query parameter: \(name)")
    }
    guard value.count <= maxQueryParamLength else {
        throw ClawMailError.invalidParameter("Query parameter '\(name)' exceeds maximum length")
    }
    return value
}

/// Get an optional String query parameter.
func optionalQueryParam(_ params: Parameters, _ name: String) -> String? {
    guard let value = params.get(name) else { return nil }
    guard value.count <= maxQueryParamLength else { return nil }
    return value
}

/// Get an optional Int query parameter with a default value. Clamps to maxResultLimit for "limit" params.
func intQueryParam(_ params: Parameters, _ name: String, default defaultValue: Int) -> Int {
    guard let value = params.get(name, as: Int.self) else {
        return defaultValue
    }
    // Cap pagination limits to prevent excessive query results
    if name == "limit" {
        return min(max(value, 1), maxResultLimit)
    }
    if name == "offset" {
        return max(value, 0)
    }
    return value
}

/// Get an optional Bool query parameter with a default value.
func boolQueryParam(_ params: Parameters, _ name: String, default defaultValue: Bool) -> Bool {
    guard let str = params.get(name) else {
        return defaultValue
    }
    return str == "true" || str == "1"
}

/// Execute a route handler with standardized ClawMailError → HTTP error mapping.
func handleRoute(_ handler: @Sendable () async throws -> Response) async -> Response {
    do {
        return try await handler()
    } catch let error as ClawMailError {
        return clawMailErrorResponse(error)
    } catch {
        return genericErrorResponse(error)
    }
}
