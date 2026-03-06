import Foundation
import Hummingbird
import ClawMailCore

// MARK: - AuditRoutes

/// Route group for audit log operations under `/api/v1/audit`.
enum AuditRoutes {

    static func register(on router: Router<BasicRequestContext>, orchestrator: AccountOrchestrator) {

        // GET /api/v1/audit — list audit entries
        router.get("api/v1/audit") { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = optionalQueryParam(qp, "account")
                let limit = intQueryParam(qp, "limit", default: 100)
                let offset = intQueryParam(qp, "offset", default: 0)
                let entries = try await orchestrator.getAuditLog(account: account, limit: limit, offset: offset)
                return jsonResponse(entries)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }
    }
}
