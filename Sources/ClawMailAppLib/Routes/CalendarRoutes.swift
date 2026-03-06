import Foundation
import Hummingbird
import ClawMailCore

// MARK: - CalendarRoutes

/// Route group for calendar operations under `/api/v1/calendar`.
enum CalendarRoutes {

    static func register(on router: Router<BasicRequestContext>, orchestrator: AccountOrchestrator) {
        let group = router.group("api/v1/calendar")

        // GET /api/v1/calendar/calendars — list calendars
        group.get("calendars") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                let calendars = try await orchestrator.listCalendars(account: account)
                return jsonResponse(calendars)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // GET /api/v1/calendar/events — list events
        group.get("events") { request, context -> Response in
            do {
                let qp = request.uri.queryParameters
                let account = try requireQueryParam(qp, "account")

                let fromStr = try requireQueryParam(qp, "from")
                guard let from = ISO8601DateFormatter().date(from: fromStr) else {
                    return badRequestResponse("Invalid 'from' date format (ISO 8601 required)")
                }

                let toStr = try requireQueryParam(qp, "to")
                guard let to = ISO8601DateFormatter().date(from: toStr) else {
                    return badRequestResponse("Invalid 'to' date format (ISO 8601 required)")
                }

                let calendar = optionalQueryParam(qp, "calendar")

                let events = try await orchestrator.listEvents(
                    account: account,
                    from: from,
                    to: to,
                    calendar: calendar
                )
                return jsonResponse(events)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // POST /api/v1/calendar/events — create event
        group.post("events") { request, context -> Response in
            do {
                let body = try await decodeBody(CreateEventRequest.self, from: request, context: context)
                let event = try await orchestrator.createEvent(account: body.account, body, interface: .rest)
                return jsonResponse(event, status: .created)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // PUT /api/v1/calendar/events/:eventId — update event
        group.put("events/:eventId") { request, context -> Response in
            do {
                guard let eventId = context.parameters.get("eventId") else {
                    return badRequestResponse("Missing eventId")
                }
                let body = try await decodeBody(UpdateEventRequest.self, from: request, context: context)
                let event = try await orchestrator.updateEvent(
                    account: body.account,
                    id: eventId,
                    body,
                    interface: .rest
                )
                return jsonResponse(event)
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }

        // DELETE /api/v1/calendar/events/:eventId — delete event
        group.delete("events/:eventId") { request, context -> Response in
            do {
                let account = try requireQueryParam(request.uri.queryParameters, "account")
                guard let eventId = context.parameters.get("eventId") else {
                    return badRequestResponse("Missing eventId")
                }
                try await orchestrator.deleteEvent(account: account, id: eventId, interface: .rest)
                return jsonResponse(["ok": true])
            } catch let error as ClawMailError {
                return clawMailErrorResponse(error)
            } catch {
                return genericErrorResponse(error)
            }
        }
    }
}
