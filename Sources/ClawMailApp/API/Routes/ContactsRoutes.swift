import Foundation
import Hummingbird
import ClawMailCore

// MARK: - ContactsRoutes

/// Route group for contact operations under `/api/v1/contacts`.
enum ContactsRoutes {

    static func register(on router: Router<BasicRequestContext>, orchestrator: AccountOrchestrator) {
        let group = router.group("api/v1/contacts")

        // GET /api/v1/contacts/address-books — list address books
        group.get("address-books") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                let addressBooks = try await orchestrator.listAddressBooks(account: account)
                return jsonResponse(addressBooks)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // GET /api/v1/contacts — list contacts
        group.get { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = try requireQueryParam(qp, "account")
                let addressBook = optionalQueryParam(qp, "addressBook")
                let query = optionalQueryParam(qp, "q")
                let limit = intQueryParam(qp, "limit", default: 100)
                let offset = intQueryParam(qp, "offset", default: 0)
                let contacts = try await orchestrator.listContacts(
                    account: account,
                    addressBook: addressBook,
                    query: query,
                    limit: limit,
                    offset: offset
                )
                return jsonResponse(contacts)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/contacts — create contact
        group.post { request, context -> Response in
            do {
                let body = try await decodeBody(CreateContactRequest.self, from: request, context: context)
                let contact = try await orchestrator.createContact(account: body.account, body)
                return jsonResponse(contact, status: .created)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // PUT /api/v1/contacts/:contactId — update contact
        group.put(":contactId") { request, context -> Response in
            do {
                guard let contactId = context.parameters.get("contactId") else {
                    return badRequestResponse("Missing contactId")
                }
                let body = try await decodeBody(UpdateContactRequest.self, from: request, context: context)
                let contact = try await orchestrator.updateContact(
                    account: body.account,
                    id: contactId,
                    body
                )
                return jsonResponse(contact)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // DELETE /api/v1/contacts/:contactId — delete contact
        group.delete(":contactId") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                guard let contactId = context.parameters.get("contactId") else {
                    return badRequestResponse("Missing contactId")
                }
                try await orchestrator.deleteContact(account: account, id: contactId)
                return jsonResponse(["ok": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }
    }
}
