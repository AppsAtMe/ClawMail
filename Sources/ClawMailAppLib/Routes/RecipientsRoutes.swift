import Foundation
import Hummingbird
import ClawMailCore

// MARK: - RecipientsRoutes

/// Route group for approved recipient operations under `/api/v1/recipients`.
enum RecipientsRoutes {

    static func register(on router: Router<BasicRequestContext>, orchestrator: AccountOrchestrator) {
        let group = router.group("api/v1/recipients")

        // GET /api/v1/recipients — list approved recipients
        group.get { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = optionalQueryParam(qp, "account")
                let recipients = try await orchestrator.listApprovedRecipients(account: account)
                let result = recipients.map { r in
                    [
                        "email": r.email,
                        "account": r.accountLabel,
                        "approvedAt": ISO8601DateFormatter().string(from: r.approvedAt),
                    ]
                }
                return jsonResponse(result)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/recipients/approve — approve one or more recipients
        group.post("approve") { request, context -> Response in
            do {
                let body = try await decodeBody(ApproveRecipientsRequest.self, from: request, context: context)
                if let emails = body.emails {
                    try await orchestrator.approvePendingRecipients(emails: emails, account: body.account)
                } else if let email = body.email {
                    try await orchestrator.approveRecipient(email: email, account: body.account)
                } else {
                    throw ClawMailError.invalidParameter("Provide 'email' or 'emails' field")
                }
                return jsonResponse(["success": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // DELETE /api/v1/recipients — remove an approved recipient
        group.delete { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = try requireQueryParam(qp, "account")
                let email = try requireQueryParam(qp, "email")
                try await orchestrator.removeApprovedRecipient(email: email, account: account)
                return jsonResponse(["success": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }
    }
}

// MARK: - Request Body

private struct ApproveRecipientsRequest: Codable {
    let account: String
    let email: String?
    let emails: [String]?
}
