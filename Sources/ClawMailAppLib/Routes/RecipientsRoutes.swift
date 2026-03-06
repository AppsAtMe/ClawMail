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

        // GET /api/v1/recipients/pending — list held send approvals
        group.get("pending") { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = optionalQueryParam(qp, "account")
                let approvals = try await orchestrator.listPendingApprovals(account: account)
                let result = approvals.map { approval in
                    PendingApprovalResponse(
                        requestId: approval.requestId,
                        account: approval.accountLabel,
                        emails: approval.emails,
                        createdAt: ISO8601DateFormatter().string(from: approval.createdAt),
                        status: approval.status.rawValue,
                        operation: approval.operation.rawValue,
                        subject: approval.subject
                    )
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
                if let requestId = body.requestId {
                    try await orchestrator.approvePendingApproval(requestId: requestId, account: body.account)
                } else if let emails = body.emails {
                    try await orchestrator.approvePendingRecipients(emails: emails, account: body.account)
                } else if let email = body.email {
                    try await orchestrator.approveRecipient(email: email, account: body.account)
                } else {
                    throw ClawMailError.invalidParameter("Provide 'requestId', 'email', or 'emails' field")
                }
                return jsonResponse(["success": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/recipients/reject — reject a held send request
        group.post("reject") { request, context -> Response in
            do {
                let body = try await decodeBody(RejectPendingApprovalRequest.self, from: request, context: context)
                try await orchestrator.rejectPendingApproval(requestId: body.requestId, account: body.account)
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
    let requestId: String?
    let email: String?
    let emails: [String]?
}

private struct RejectPendingApprovalRequest: Codable {
    let account: String
    let requestId: String
}

private struct PendingApprovalResponse: Codable, Sendable {
    let requestId: String
    let account: String
    let emails: [String]
    let createdAt: String
    let status: String
    let operation: String
    let subject: String?
}
