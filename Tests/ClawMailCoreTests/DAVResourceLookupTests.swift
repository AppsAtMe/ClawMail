import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ClawMailCore

@Suite(.serialized)
struct DAVResourceLookupTests {

    @Test func calendarManagerUpdatesUsingUIDLookupAndResolvedHref() async throws {
        let session = makeSession()
        let eventID = "event-123"
        let eventHref = "/calendars/user/work/server-assigned.ics"

        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.principalBody(property: "current-user-principal", href: "/principals/user/")
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.principalBody(property: "calendar-home-set", href: "/calendars/user/")
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.calendarListingBody(
                    href: "/calendars/user/work/",
                    displayName: "Work",
                    components: ["VEVENT"]
                )
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            #expect(request.httpMethod == "REPORT")
            #expect(request.url?.path == "/calendars/user/work")

            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains(#"<c:prop-filter name="UID">"#))
            #expect(body.contains(eventID))
            #expect(!body.contains("<c:time-range"))

            return self.response(
                url: request.url!,
                body: self.calendarDataBody(
                    resourceHref: eventHref,
                    payload: """
                    BEGIN:VCALENDAR
                    VERSION:2.0
                    BEGIN:VEVENT
                    UID:event-123
                    DTSTART:20260306T120000Z
                    DTEND:20260306T130000Z
                    SUMMARY:Original Title
                    LOCATION:Old Room
                    DESCRIPTION:Original Description
                    END:VEVENT
                    END:VCALENDAR
                    """
                )
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == eventHref)

            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains("UID:event-123"))
            #expect(body.contains("SUMMARY:Updated Title"))

            return self.response(url: request.url!, status: 204, body: "")
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://calendar.example.com/dav")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )
        let manager = CalendarManager(client: client)

        let updated = try await manager.updateEvent(
            id: eventID,
            UpdateEventRequest(account: "Work", title: "Updated Title")
        )

        #expect(updated.id == eventID)
        #expect(updated.title == "Updated Title")
        #expect(MockDAVLookupURLProtocol.recordedRequests().count == 5)
    }

    @Test func taskManagerDeletesUsingUIDLookupAndResolvedHref() async throws {
        let session = makeSession()
        let taskID = "task-123"
        let taskHref = "/calendars/user/tasks/custom-task.ics"

        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.principalBody(property: "current-user-principal", href: "/principals/user/")
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.principalBody(property: "calendar-home-set", href: "/calendars/user/")
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.calendarListingBody(
                    href: "/calendars/user/tasks/",
                    displayName: "Tasks",
                    components: ["VTODO"]
                )
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            #expect(request.httpMethod == "REPORT")
            #expect(request.url?.path == "/calendars/user/tasks")

            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains(#"<c:comp-filter name="VTODO">"#))
            #expect(body.contains(#"<c:prop-filter name="UID">"#))
            #expect(!body.contains(#"<c:prop-filter name="STATUS">"#))

            return self.response(
                url: request.url!,
                body: self.calendarDataBody(
                    resourceHref: taskHref,
                    payload: """
                    BEGIN:VCALENDAR
                    VERSION:2.0
                    BEGIN:VTODO
                    UID:task-123
                    SUMMARY:Finish review
                    STATUS:COMPLETED
                    END:VTODO
                    END:VCALENDAR
                    """
                )
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == taskHref)
            return self.response(url: request.url!, status: 204, body: "")
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://calendar.example.com/dav")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )
        let manager = TaskManager(client: client)

        try await manager.deleteTask(id: taskID)

        #expect(MockDAVLookupURLProtocol.recordedRequests().count == 5)
    }

    @Test func contactsManagerDeletesUsingUIDLookupAndResolvedHref() async throws {
        let session = makeSession()
        let contactID = "contact-123"
        let contactHref = "/addressbooks/user/default/server-contact.vcf"

        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.principalBody(property: "current-user-principal", href: "/principals/user/")
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.principalBody(property: "addressbook-home-set", href: "/addressbooks/user/")
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.addressBookListingBody(
                    href: "/addressbooks/user/default/",
                    displayName: "Default"
                )
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            #expect(request.httpMethod == "REPORT")
            #expect(request.url?.path == "/addressbooks/user/default")

            let body = String(data: requestBody(for: request), encoding: .utf8) ?? ""
            #expect(body.contains(#"<card:prop-filter name="UID">"#))
            #expect(body.contains(contactID))
            #expect(!body.contains(#"<card:prop-filter name="FN">"#))

            return self.response(
                url: request.url!,
                body: self.addressDataBody(
                    resourceHref: contactHref,
                    payload: """
                    BEGIN:VCARD
                    VERSION:3.0
                    UID:contact-123
                    FN:Test Contact
                    N:Contact;Test;;;
                    EMAIL:test@example.com
                    END:VCARD
                    """
                )
            )
        }
        MockDAVLookupURLProtocol.enqueue { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == contactHref)
            return self.response(url: request.url!, status: 204, body: "")
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://contacts.example.com/dav")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )
        let manager = ContactsManager(client: client)

        try await manager.deleteContact(id: contactID)

        #expect(MockDAVLookupURLProtocol.recordedRequests().count == 5)
    }

    private func makeSession() -> URLSession {
        MockDAVLookupURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDAVLookupURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(url: URL, status: Int = 207, body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }

    private func principalBody(property: String, href: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat>
              <d:prop>
                <d:\(property)>
                  <d:href>\(href)</d:href>
                </d:\(property)>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
    }

    private func calendarListingBody(href: String, displayName: String, components: [String]) -> String {
        let componentXML = components.map { #"<c:comp name="\#($0)"/>"# }.joined(separator: "\n                      ")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>\(href)</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>\(displayName)</d:displayname>
                <d:resourcetype>
                  <d:collection/>
                  <c:calendar/>
                </d:resourcetype>
                <c:supported-calendar-component-set>
                  \(componentXML)
                </c:supported-calendar-component-set>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
    }

    private func calendarDataBody(resourceHref: String, payload: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:response>
            <d:href>\(resourceHref)</d:href>
            <d:propstat>
              <d:prop>
                <c:calendar-data>\(payload)</c:calendar-data>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
    }

    private func addressBookListingBody(href: String, displayName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:response>
            <d:href>\(href)</d:href>
            <d:propstat>
              <d:prop>
                <d:displayname>\(displayName)</d:displayname>
                <d:resourcetype>
                  <d:collection/>
                  <card:addressbook/>
                </d:resourcetype>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
    }

    private func addressDataBody(resourceHref: String, payload: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:response>
            <d:href>\(resourceHref)</d:href>
            <d:propstat>
              <d:prop>
                <card:address-data>\(payload)</card:address-data>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        </d:multistatus>
        """
    }
}

private func requestBody(for request: URLRequest) -> Data {
    if let httpBody = request.httpBody {
        return httpBody
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        guard bytesRead > 0 else { break }
        data.append(buffer, count: bytesRead)
    }
    return data
}

private final class MockDAVLookupURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [@Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = []
    private nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers = []
        requests = []
    }

    static func enqueue(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(handler)
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
        Self.lock.lock()
        Self.requests.append(request)
        handler = Self.handlers.isEmpty ? nil : Self.handlers.removeFirst()
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: ClawMailError.serverError("No mock response configured"))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
