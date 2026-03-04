import Foundation
import Hummingbird
import ClawMailCore

// MARK: - EmailRoutes

/// Route group for email operations under `/api/v1/email`.
enum EmailRoutes {

    static func register(on router: Router<BasicRequestContext>, orchestrator: AccountOrchestrator) {
        let group = router.group("api/v1/email")

        // GET /api/v1/email — list messages
        group.get { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = try requireQueryParam(qp, "account")
                let folder = optionalQueryParam(qp, "folder") ?? "INBOX"
                let limit = intQueryParam(qp, "limit", default: 50)
                let offset = intQueryParam(qp, "offset", default: 0)
                let messages = try await orchestrator.listMessages(
                    account: account,
                    folder: folder,
                    limit: limit,
                    offset: offset
                )
                return jsonResponse(messages)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // GET /api/v1/email/search — search messages
        group.get("search") { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = try requireQueryParam(qp, "account")
                let query = try requireQueryParam(qp, "q")
                let folder = optionalQueryParam(qp, "folder")
                let limit = intQueryParam(qp, "limit", default: 50)
                let offset = intQueryParam(qp, "offset", default: 0)
                let results = try await orchestrator.searchMessages(
                    account: account,
                    query: query,
                    folder: folder,
                    limit: limit,
                    offset: offset
                )
                return jsonResponse(results)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // GET /api/v1/email/folders — list folders
        group.get("folders") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                let folders = try await orchestrator.listFolders(account: account)
                return jsonResponse(folders)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/email/folders — create folder
        group.post("folders") { request, context -> Response in
            do {
                let body = try await decodeBody(CreateFolderRequest.self, from: request, context: context)
                try await orchestrator.createFolder(
                    account: body.account,
                    name: body.name,
                    parent: body.parent
                )
                return jsonResponse(["ok": true], status: .created)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // DELETE /api/v1/email/folders/:path — delete folder
        group.delete("folders/:path") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                guard let path = context.parameters.get("path") else {
                    return badRequestResponse("Missing folder path")
                }
                let decodedPath = path.removingPercentEncoding ?? path
                try await orchestrator.deleteFolder(account: account, path: decodedPath)
                return jsonResponse(["ok": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/email/send — send message
        group.post("send") { request, context -> Response in
            do {
                let body = try await decodeBody(SendEmailRequest.self, from: request, context: context)
                let messageId = try await orchestrator.sendMessage(body)
                return jsonResponse(["messageId": messageId], status: .created)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/email/reply — reply to message
        group.post("reply") { request, context -> Response in
            do {
                let body = try await decodeBody(ReplyEmailRequest.self, from: request, context: context)
                let messageId = try await orchestrator.replyToMessage(body)
                return jsonResponse(["messageId": messageId], status: .created)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/email/forward — forward message
        group.post("forward") { request, context -> Response in
            do {
                let body = try await decodeBody(ForwardEmailRequest.self, from: request, context: context)
                let messageId = try await orchestrator.forwardMessage(body)
                return jsonResponse(["messageId": messageId], status: .created)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // GET /api/v1/email/:messageId — read a single message
        group.get(":messageId") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                guard let messageId = context.parameters.get("messageId") else {
                    return badRequestResponse("Missing messageId")
                }
                let message = try await orchestrator.readMessage(account: account, id: messageId)
                return jsonResponse(message)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // PATCH /api/v1/email/:messageId — move or update flags
        group.patch(":messageId") { request, context -> Response in
            do {
                guard let messageId = context.parameters.get("messageId") else {
                    return badRequestResponse("Missing messageId")
                }
                let body = try await decodeBody(PatchMessageRequest.self, from: request, context: context)

                // Move to folder if specified
                if let destination = body.moveTo {
                    try await orchestrator.moveMessage(
                        account: body.account,
                        id: messageId,
                        to: destination
                    )
                }

                // Update flags if specified
                if let addFlags = body.addFlags, !addFlags.isEmpty {
                    try await orchestrator.updateFlags(
                        account: body.account,
                        id: messageId,
                        add: addFlags
                    )
                }
                if let removeFlags = body.removeFlags, !removeFlags.isEmpty {
                    try await orchestrator.updateFlags(
                        account: body.account,
                        id: messageId,
                        remove: removeFlags
                    )
                }

                return jsonResponse(["ok": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // DELETE /api/v1/email/:messageId — delete message
        group.delete(":messageId") { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = try requireQueryParam(qp, "account")
                guard let messageId = context.parameters.get("messageId") else {
                    return badRequestResponse("Missing messageId")
                }
                let permanent = boolQueryParam(qp, "permanent", default: false)
                try await orchestrator.deleteMessage(
                    account: account,
                    id: messageId,
                    permanent: permanent
                )
                return jsonResponse(["ok": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // GET /api/v1/email/:messageId/attachments/:filename — download attachment
        group.get(":messageId/attachments/:filename") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                guard let messageId = context.parameters.get("messageId") else {
                    return badRequestResponse("Missing messageId")
                }
                guard let filename = context.parameters.get("filename") else {
                    return badRequestResponse("Missing filename")
                }
                let decodedFilename = filename.removingPercentEncoding ?? filename

                // Download to a temporary path
                let tempDir = NSTemporaryDirectory()
                let tempPath = (tempDir as NSString).appendingPathComponent(decodedFilename)

                let result = try await orchestrator.downloadAttachment(
                    account: account,
                    messageId: messageId,
                    filename: decodedFilename,
                    path: tempPath
                )

                return jsonResponse(AttachmentDownloadResult(path: result.path, size: result.size))
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }
    }
}

// MARK: - Request/Response Types

/// Request body for PATCH /api/v1/email/:messageId
struct PatchMessageRequest: Codable, Sendable {
    var account: String
    var moveTo: String?
    var addFlags: [EmailFlag]?
    var removeFlags: [EmailFlag]?
}

/// Request body for POST /api/v1/email/folders
struct CreateFolderRequest: Codable, Sendable {
    var account: String
    var name: String
    var parent: String?
}

/// Response for attachment download
struct AttachmentDownloadResult: Codable, Sendable {
    var path: String
    var size: Int
}
