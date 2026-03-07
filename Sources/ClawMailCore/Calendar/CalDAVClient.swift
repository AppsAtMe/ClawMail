import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - CalDAV Data Types

/// Represents a calendar discovered via CalDAV PROPFIND.
public struct CalDAVCalendar: Codable, Sendable, Equatable {
    public var href: String
    public var displayName: String
    public var color: String?
    public var supportedComponents: Set<String>

    public init(href: String, displayName: String, color: String? = nil, supportedComponents: Set<String> = ["VEVENT"]) {
        self.href = href
        self.displayName = displayName
        self.color = color
        self.supportedComponents = supportedComponents
    }

    public var supportsEvents: Bool {
        supportedComponents.contains("VEVENT")
    }

    public var supportsTasks: Bool {
        supportedComponents.contains("VTODO")
    }
}

struct CalDAVResource: Sendable, Equatable {
    var href: String
    var calendarData: String
}

/// Credential used for CalDAV authentication.
public enum CalDAVCredential: Sendable {
    case password(username: String, password: String)
    case oauthToken(OAuthTokenProvider)
}

// MARK: - CalDAVClient

/// Actor-based CalDAV client using URLSession for HTTP.
///
/// CalDAV is a WebDAV extension over HTTP that uses XML for requests/responses
/// and iCalendar (RFC 5545) for event/task payloads.
public actor CalDAVClient {

    // MARK: - Properties

    private let credential: CalDAVCredential
    private let session: URLSession
    private var serverURL: URL
    private var calendarHomePath: String?

    // MARK: - Initialization

    public init(baseURL: URL, credential: CalDAVCredential, session: URLSession? = nil) throws {
        let validatedBaseURL = try DAVURLValidator.validateConfiguredURL(baseURL, serviceName: "CalDAV")
        self.credential = credential
        self.session = session ?? URLSession.shared
        self.serverURL = validatedBaseURL
    }

    // MARK: - Discovery

    /// Attempt auto-discovery of CalDAV endpoint from an email address.
    /// Tries well-known URL path first, then falls back to common CalDAV paths.
    public func discover(from email: String) async throws -> URL? {
        let domain = email.components(separatedBy: "@").last ?? ""
        guard !domain.isEmpty else { return nil }

        // Try .well-known/caldav
        let wellKnownURLs = [
            URL(string: "https://\(domain)/.well-known/caldav"),
            URL(string: "https://\(domain)/remote.php/dav"),
            URL(string: "https://\(domain)/dav"),
        ].compactMap { $0 }

        for url in wellKnownURLs {
            var request = URLRequest(url: url)
            request.httpMethod = "PROPFIND"
            request.setValue("0", forHTTPHeaderField: "Depth")
            request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
            try await applyAuth(to: &request)

            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...399).contains(httpResponse.statusCode) {
                    // If redirected, follow the Location header
                    if let location = httpResponse.value(forHTTPHeaderField: "Location"),
                       let redirectURL = URL(string: location) {
                        return redirectURL
                    }
                    return url
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Test authentication by performing a basic PROPFIND on the base URL.
    public func authenticate() async throws {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = WebDAVXMLBuilder.propfind(properties: ["d:current-user-principal"])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawMailError.connectionError("Invalid response from CalDAV server")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClawMailError.authFailed("CalDAV authentication failed (HTTP \(httpResponse.statusCode))")
        }

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 else {
            throw ClawMailError.connectionError("CalDAV server returned HTTP \(httpResponse.statusCode)")
        }

        // Try to extract current-user-principal for later use
        let parsed = WebDAVResponseParser.parse(data: data)
        if let principal = parsed.first?.properties["current-user-principal"] {
            // Discover calendar-home-set from the principal
            try await discoverCalendarHome(principalPath: principal)
        }
    }

    // MARK: - Calendar Operations

    /// List all calendars from the calendar-home-set.
    public func listCalendars() async throws -> [CalDAVCalendar] {
        let homeURL = try await resolveCalendarHomeURL()

        var request = URLRequest(url: homeURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = WebDAVXMLBuilder.propfind(properties: [
            "d:displayname",
            "d:resourcetype",
            "apple:calendar-color",
            "c:supported-calendar-component-set",
        ])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "listCalendars")

        let responses = WebDAVResponseParser.parse(data: data)
        var calendars: [CalDAVCalendar] = []

        for item in responses {
            // Only include actual calendar collections (skip the home itself)
            guard item.isCalendarCollection else { continue }
            let hrefURL = try resolveServerURL(item.href, context: "listCalendars href")

            let components = item.supportedComponents
            let calendar = CalDAVCalendar(
                href: hrefURL.path,
                displayName: item.properties["displayname"] ?? item.href.lastPathComponent,
                color: item.properties["calendar-color"],
                supportedComponents: components.isEmpty ? Set(["VEVENT"]) : components
            )
            calendars.append(calendar)
        }

        return calendars
    }

    /// Retrieve events from a calendar within a date range using REPORT calendar-query.
    public func getEvents(calendar: String, from startDate: Date, to endDate: Date) async throws -> [String] {
        let calURL = try resolveServerURL(calendar, context: "getEvents calendar")

        var request = URLRequest(url: calURL)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = WebDAVXMLBuilder.calendarQuery(
            componentType: "VEVENT",
            startDate: startDate,
            endDate: endDate
        )
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "getEvents")

        let responses = WebDAVResponseParser.parse(data: data)
        return responses.compactMap { $0.calendarData }
    }

    func findEvent(calendar: String, uid: String) async throws -> CalDAVResource? {
        let calURL = try resolveServerURL(calendar, context: "findEvent calendar")

        var request = URLRequest(url: calURL)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)
        request.httpBody = WebDAVXMLBuilder.calendarUIDQuery(componentType: "VEVENT", uid: uid).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "findEvent")

        let responses = WebDAVResponseParser.parse(data: data)
        for item in responses {
            guard let calendarData = item.calendarData else { continue }
            let hrefURL = try resolveServerURL(item.href, context: "findEvent href")
            return CalDAVResource(href: hrefURL.path, calendarData: calendarData)
        }

        return nil
    }

    /// Create a new event in a calendar. Returns the href of the created resource.
    public func createEvent(calendar: String, icalendar: String) async throws -> String {
        let uid = ICalendarParser.extractUID(from: icalendar) ?? UUID().uuidString
        let resourcePath = calendar.hasSuffix("/") ? "\(calendar)\(uid).ics" : "\(calendar)/\(uid).ics"
        let resourceURL = try resolveServerURL(resourcePath, context: "createEvent resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "PUT"
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        try await applyAuth(to: &request)
        request.httpBody = icalendar.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "createEvent", allowedCodes: [201, 204])

        return resourcePath
    }

    /// Update an existing event.
    public func updateEvent(calendar: String, uid: String, icalendar: String) async throws {
        let resourcePath = calendar.hasSuffix("/") ? "\(calendar)\(uid).ics" : "\(calendar)/\(uid).ics"
        try await updateEvent(resourceHref: resourcePath, icalendar: icalendar)
    }

    func updateEvent(resourceHref: String, icalendar: String) async throws {
        let resourceURL = try resolveServerURL(resourceHref, context: "updateEvent resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "PUT"
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)
        request.httpBody = icalendar.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "updateEvent", allowedCodes: [200, 201, 204])
    }

    /// Delete an event by UID.
    public func deleteEvent(calendar: String, uid: String) async throws {
        let resourcePath = calendar.hasSuffix("/") ? "\(calendar)\(uid).ics" : "\(calendar)/\(uid).ics"
        try await deleteEvent(resourceHref: resourcePath)
    }

    func deleteEvent(resourceHref: String) async throws {
        let resourceURL = try resolveServerURL(resourceHref, context: "deleteEvent resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "DELETE"
        try await applyAuth(to: &request)

        let (_, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "deleteEvent", allowedCodes: [200, 204])
    }

    // MARK: - Task (VTODO) Operations

    /// List task lists (calendars that support VTODO).
    public func listTaskLists() async throws -> [CalDAVCalendar] {
        let allCalendars = try await listCalendars()
        return allCalendars.filter { $0.supportsTasks }
    }

    /// Retrieve tasks (VTODOs) from a task list.
    public func getTasks(taskList: String, includeCompleted: Bool = true) async throws -> [String] {
        let listURL = try resolveServerURL(taskList, context: "getTasks task list")

        var request = URLRequest(url: listURL)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = WebDAVXMLBuilder.calendarQueryTasks(includeCompleted: includeCompleted)
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "getTasks")

        let responses = WebDAVResponseParser.parse(data: data)
        return responses.compactMap { $0.calendarData }
    }

    func findTask(taskList: String, uid: String, includeCompleted: Bool = true) async throws -> CalDAVResource? {
        let listURL = try resolveServerURL(taskList, context: "findTask task list")

        var request = URLRequest(url: listURL)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)
        request.httpBody = WebDAVXMLBuilder.calendarUIDQuery(
            componentType: "VTODO",
            uid: uid,
            includeCompleted: includeCompleted
        ).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "findTask")

        let responses = WebDAVResponseParser.parse(data: data)
        for item in responses {
            guard let calendarData = item.calendarData else { continue }
            let hrefURL = try resolveServerURL(item.href, context: "findTask href")
            return CalDAVResource(href: hrefURL.path, calendarData: calendarData)
        }

        return nil
    }

    /// Create a new task. Returns the href of the created resource.
    public func createTask(taskList: String, icalendar: String) async throws -> String {
        let uid = ICalendarParser.extractUID(from: icalendar) ?? UUID().uuidString
        let resourcePath = taskList.hasSuffix("/") ? "\(taskList)\(uid).ics" : "\(taskList)/\(uid).ics"
        let resourceURL = try resolveServerURL(resourcePath, context: "createTask resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "PUT"
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        try await applyAuth(to: &request)
        request.httpBody = icalendar.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "createTask", allowedCodes: [201, 204])

        return resourcePath
    }

    /// Update an existing task.
    public func updateTask(taskList: String, uid: String, icalendar: String) async throws {
        let resourcePath = taskList.hasSuffix("/") ? "\(taskList)\(uid).ics" : "\(taskList)/\(uid).ics"
        try await updateTask(resourceHref: resourcePath, icalendar: icalendar)
    }

    func updateTask(resourceHref: String, icalendar: String) async throws {
        let resourceURL = try resolveServerURL(resourceHref, context: "updateTask resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "PUT"
        request.setValue("text/calendar; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)
        request.httpBody = icalendar.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "updateTask", allowedCodes: [200, 201, 204])
    }

    /// Delete a task by UID.
    public func deleteTask(taskList: String, uid: String) async throws {
        let resourcePath = taskList.hasSuffix("/") ? "\(taskList)\(uid).ics" : "\(taskList)/\(uid).ics"
        try await deleteTask(resourceHref: resourcePath)
    }

    func deleteTask(resourceHref: String) async throws {
        let resourceURL = try resolveServerURL(resourceHref, context: "deleteTask resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "DELETE"
        try await applyAuth(to: &request)

        let (_, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "deleteTask", allowedCodes: [200, 204])
    }

    // MARK: - Private Helpers

    private func applyAuth(to request: inout URLRequest) async throws {
        switch credential {
        case .password(let username, let password):
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }
        case .oauthToken(let tokenProvider):
            let token = try await tokenProvider.accessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validateResponse(
        _ response: URLResponse,
        context: String,
        allowedCodes: Set<Int> = [200, 207]
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawMailError.connectionError("\(context): Invalid response")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClawMailError.authFailed("CalDAV \(context): Authentication failed")
        }
        guard allowedCodes.contains(httpResponse.statusCode) else {
            throw ClawMailError.serverError("CalDAV \(context): HTTP \(httpResponse.statusCode)")
        }
    }

    private func updateServerURL(from response: URLResponse) throws {
        guard let effectiveURL = response.url else { return }
        serverURL = try DAVURLValidator.validateConfiguredURL(effectiveURL, serviceName: "CalDAV")
    }

    private func discoverCalendarHome(principalPath: String) async throws {
        let principalURL = try resolveServerURL(principalPath, context: "discoverCalendarHome principal")

        var request = URLRequest(url: principalURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = WebDAVXMLBuilder.propfind(properties: ["c:calendar-home-set"])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try updateServerURL(from: response)
        let responses = WebDAVResponseParser.parse(data: data)
        if let home = responses.first?.properties["calendar-home-set"] {
            let homeURL = try resolveServerURL(home, context: "discoverCalendarHome home-set")
            self.calendarHomePath = storedServerReference(for: homeURL)
        }
    }

    private func resolveCalendarHomeURL() async throws -> URL {
        if let home = calendarHomePath {
            return try resolveServerURL(home, context: "resolveCalendarHome")
        }
        // If we don't have a calendar home yet, try to discover it
        try await authenticate()
        // If still no calendar home, use the base URL path
        return try resolveServerURL(calendarHomePath ?? serverURL.path, context: "resolveCalendarHome")
    }

    private func resolveServerURL(_ path: String, context: String) throws -> URL {
        try DAVURLValidator.resolveServerURL(
            path,
            relativeTo: serverURL,
            serviceName: "CalDAV",
            context: context
        )
    }

    private func storedServerReference(for url: URL) -> String {
        if url.host?.lowercased() != serverURL.host?.lowercased() {
            return url.absoluteString
        }
        return url.path
    }
}

// MARK: - WebDAV XML Builder

/// Builds XML bodies for WebDAV/CalDAV requests.
enum WebDAVXMLBuilder: Sendable {

    /// Build a PROPFIND XML body requesting specific properties.
    static func propfind(properties: [String]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:apple="http://apple.com/ns/ical/" xmlns:cs="http://calendarserver.org/ns/" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop>

        """
        for prop in properties {
            xml += "    <\(prop)/>\n"
        }
        xml += """
          </d:prop>
        </d:propfind>
        """
        return xml
    }

    /// Build a REPORT body for calendar-query filtering by VEVENT and date range.
    static func calendarQuery(componentType: String, startDate: Date, endDate: Date) -> String {
        let formatter = ICalendarDateFormatter.shared
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag/>
            <c:calendar-data/>
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="\(componentType)">
                <c:time-range start="\(start)" end="\(end)"/>
              </c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """
    }

    /// Build a REPORT body for querying VTODO items.
    static func calendarQueryTasks(includeCompleted: Bool) -> String {
        var filterContent = ""
        if !includeCompleted {
            filterContent = """
                    <c:prop-filter name="STATUS">
                      <c:text-match negate-condition="yes">COMPLETED</c:text-match>
                    </c:prop-filter>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag/>
            <c:calendar-data/>
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="VTODO">
        \(filterContent)
              </c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """
    }

    static func calendarUIDQuery(componentType: String, uid: String, includeCompleted: Bool = true) -> String {
        let escapedUID = xmlEscape(uid)

        var filterContent = """
                <c:prop-filter name="UID">
                  <c:text-match collation="i;octet">\(escapedUID)</c:text-match>
                </c:prop-filter>
        """

        if componentType == "VTODO", !includeCompleted {
            filterContent += """

                <c:prop-filter name="STATUS">
                  <c:text-match negate-condition="yes">COMPLETED</c:text-match>
                </c:prop-filter>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag/>
            <c:calendar-data/>
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="\(componentType)">
        \(filterContent)
              </c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - WebDAV Response Parser

/// Parsed single response from a WebDAV multistatus response.
struct WebDAVResponseItem: Sendable {
    var href: String
    var statusCode: Int
    var properties: [String: String]
    var calendarData: String?
    var isCalendarCollection: Bool
    var supportedComponents: Set<String>
}

/// Parses WebDAV multistatus XML responses.
enum WebDAVResponseParser: Sendable {

    static func parse(data: Data) -> [WebDAVResponseItem] {
        let parser = WebDAVXMLParserDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.items
    }
}

/// XMLParser delegate for WebDAV multistatus responses.
private final class WebDAVXMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    var items: [WebDAVResponseItem] = []
    private var currentItem: WebDAVResponseItem?
    private var currentElement: String = ""
    private var currentText: String = ""
    private var inResponse: Bool = false
    private var inPropStat: Bool = false
    private var inProp: Bool = false
    private var inCalendarData: Bool = false
    private var inCalendarCollection: Bool = false
    private var inSupportedComponent: Bool = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let localName = elementName.localXMLName
        currentElement = localName
        currentText = ""

        switch localName {
        case "response":
            inResponse = true
            currentItem = WebDAVResponseItem(
                href: "",
                statusCode: 200,
                properties: [:],
                calendarData: nil,
                isCalendarCollection: false,
                supportedComponents: Set()
            )
        case "propstat":
            inPropStat = true
        case "prop":
            if inPropStat {
                inProp = true
            }
        case "calendar-data":
            inCalendarData = true
        case "calendar", "C:calendar":
            if inProp {
                currentItem?.isCalendarCollection = true
            }
        case "comp":
            if inProp, let name = attributes["name"] {
                currentItem?.supportedComponents.insert(name)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let localName = elementName.localXMLName
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch localName {
        case "response":
            if let item = currentItem {
                items.append(item)
            }
            currentItem = nil
            inResponse = false
        case "propstat":
            inPropStat = false
        case "prop":
            inProp = false
        case "href":
            if inProp {
                // href inside a property (like calendar-home-set or current-user-principal)
                let propName: String
                // Store as the parent property
                if currentItem != nil {
                    // We just use a generic key; the caller will check for it
                    propName = "calendar-home-set"
                    currentItem?.properties[propName] = trimmed
                    currentItem?.properties["current-user-principal"] = trimmed
                }
            } else if inResponse && currentItem != nil {
                currentItem?.href = trimmed
            }
        case "displayname":
            if inProp {
                currentItem?.properties["displayname"] = trimmed
            }
        case "calendar-color":
            if inProp {
                currentItem?.properties["calendar-color"] = trimmed
            }
        case "calendar-data":
            if inProp {
                currentItem?.calendarData = currentText
            }
            inCalendarData = false
        case "status":
            if inPropStat, trimmed.contains("200") {
                // status OK
            }
        default:
            if inProp && !trimmed.isEmpty {
                currentItem?.properties[localName] = trimmed
            }
        }

        currentText = ""
    }
}

// MARK: - iCalendar Date Formatter

/// Shared UTC date formatter for iCalendar date-time values.
final class ICalendarDateFormatter: @unchecked Sendable {
    static let shared = ICalendarDateFormatter()

    private let utcFormatter: DateFormatter
    private let dateOnlyFormatter: DateFormatter

    private init() {
        utcFormatter = DateFormatter()
        utcFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        utcFormatter.timeZone = TimeZone(identifier: "UTC")
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")

        dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyyMMdd"
        dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
    }

    func string(from date: Date) -> String {
        utcFormatter.string(from: date)
    }

    func dateOnlyString(from date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    func date(from string: String) -> Date? {
        // Try full datetime first
        if let d = utcFormatter.date(from: string) {
            return d
        }
        // Try date-only (VALUE=DATE)
        if let d = dateOnlyFormatter.date(from: string) {
            return d
        }
        // Try without trailing Z (local time)
        let noZ = string.replacingOccurrences(of: "Z", with: "")
        let localFormatter = DateFormatter()
        localFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        localFormatter.timeZone = TimeZone(identifier: "UTC")
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        return localFormatter.date(from: noZ)
    }
}

// MARK: - iCalendar Parser

/// Parses iCalendar (RFC 5545) text into structured properties.
public enum ICalendarParser: Sendable {

    /// Parsed representation of a VEVENT component.
    public struct ParsedEvent: Sendable {
        public var uid: String
        public var summary: String?
        public var dtstart: Date?
        public var dtend: Date?
        public var location: String?
        public var description: String?
        public var attendees: [(name: String?, email: String, status: String)]
        public var recurrence: String?
        public var allDay: Bool
        public var reminders: [Int] // minutes before

        public init(
            uid: String = "",
            summary: String? = nil,
            dtstart: Date? = nil,
            dtend: Date? = nil,
            location: String? = nil,
            description: String? = nil,
            attendees: [(name: String?, email: String, status: String)] = [],
            recurrence: String? = nil,
            allDay: Bool = false,
            reminders: [Int] = []
        ) {
            self.uid = uid
            self.summary = summary
            self.dtstart = dtstart
            self.dtend = dtend
            self.location = location
            self.description = description
            self.attendees = attendees
            self.recurrence = recurrence
            self.allDay = allDay
            self.reminders = reminders
        }
    }

    /// Parse iCalendar text and extract VEVENT components.
    public static func parseEvents(from icalendar: String) -> [ParsedEvent] {
        let unfolded = unfoldLines(icalendar)
        let lines = unfolded.components(separatedBy: "\n")

        var events: [ParsedEvent] = []
        var current: ParsedEvent?
        var inVEvent = false
        var inVAlarm = false
        var alarmTrigger: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed == "BEGIN:VEVENT" {
                inVEvent = true
                current = ParsedEvent()
                continue
            }
            if trimmed == "END:VEVENT" {
                if let event = current {
                    events.append(event)
                }
                current = nil
                inVEvent = false
                continue
            }
            if trimmed == "BEGIN:VALARM" {
                inVAlarm = true
                alarmTrigger = nil
                continue
            }
            if trimmed == "END:VALARM" {
                if inVAlarm, let trigger = alarmTrigger {
                    if let minutes = parseTriggerMinutes(trigger) {
                        current?.reminders.append(minutes)
                    }
                }
                inVAlarm = false
                continue
            }

            guard inVEvent else { continue }

            if inVAlarm {
                let (key, value) = splitProperty(trimmed)
                let baseKey = key.components(separatedBy: ";").first ?? key
                switch baseKey {
                case "TRIGGER": alarmTrigger = value
                default: break
                }
                continue
            }

            let (key, value) = splitProperty(trimmed)
            let baseKey = key.components(separatedBy: ";").first ?? key

            switch baseKey {
            case "UID":
                current?.uid = value
            case "SUMMARY":
                current?.summary = unescapeICalValue(value)
            case "DTSTART":
                if key.contains("VALUE=DATE") && !key.contains("DATE-TIME") {
                    current?.allDay = true
                }
                current?.dtstart = ICalendarDateFormatter.shared.date(from: value)
            case "DTEND":
                current?.dtend = ICalendarDateFormatter.shared.date(from: value)
            case "LOCATION":
                current?.location = unescapeICalValue(value)
            case "DESCRIPTION":
                current?.description = unescapeICalValue(value)
            case "RRULE":
                current?.recurrence = value
            case "ATTENDEE":
                let email = extractMailto(value)
                let name = extractParam(key, param: "CN")
                let partstat = extractParam(key, param: "PARTSTAT") ?? "NEEDS-ACTION"
                if let email = email {
                    current?.attendees.append((name: name, email: email, status: partstat))
                }
            default:
                break
            }
        }

        return events
    }

    /// Extract UID from raw iCalendar text.
    public static func extractUID(from icalendar: String) -> String? {
        let unfolded = unfoldLines(icalendar)
        for line in unfolded.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("UID:") {
                return String(trimmed.dropFirst(4))
            }
        }
        return nil
    }

    /// Build an iCalendar VCALENDAR/VEVENT string from structured data.
    public static func buildEvent(
        uid: String,
        summary: String,
        start: Date,
        end: Date,
        location: String? = nil,
        description: String? = nil,
        attendees: [(name: String?, email: String)] = [],
        recurrence: String? = nil,
        allDay: Bool = false,
        reminders: [Int] = []
    ) -> String {
        let formatter = ICalendarDateFormatter.shared
        let now = formatter.string(from: Date())

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//ClawMail//CalDAV Client//EN",
            "BEGIN:VEVENT",
            "UID:\(uid)",
            "DTSTAMP:\(now)",
        ]

        if allDay {
            lines.append("DTSTART;VALUE=DATE:\(formatter.dateOnlyString(from: start))")
            lines.append("DTEND;VALUE=DATE:\(formatter.dateOnlyString(from: end))")
        } else {
            lines.append("DTSTART:\(formatter.string(from: start))")
            lines.append("DTEND:\(formatter.string(from: end))")
        }

        lines.append("SUMMARY:\(escapeICalValue(summary))")

        if let location = location {
            lines.append("LOCATION:\(escapeICalValue(location))")
        }
        if let description = description {
            lines.append("DESCRIPTION:\(escapeICalValue(description))")
        }
        if let recurrence = recurrence {
            lines.append("RRULE:\(recurrence)")
        }

        for attendee in attendees {
            var params = "ATTENDEE"
            if let name = attendee.name {
                params += ";CN=\(name)"
            }
            params += ";PARTSTAT=NEEDS-ACTION:mailto:\(attendee.email)"
            lines.append(params)
        }

        for minutes in reminders {
            lines.append("BEGIN:VALARM")
            lines.append("ACTION:DISPLAY")
            lines.append("DESCRIPTION:Reminder")
            lines.append("TRIGGER:-PT\(minutes)M")
            lines.append("END:VALARM")
        }

        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Internal Helpers

    /// Unfold iCalendar line continuations (lines starting with space/tab are continuations).
    static func unfoldLines(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\r\n ", with: "")
        result = result.replacingOccurrences(of: "\r\n\t", with: "")
        result = result.replacingOccurrences(of: "\n ", with: "")
        result = result.replacingOccurrences(of: "\n\t", with: "")
        return result
    }

    /// Split an iCalendar property line into key (with params) and value.
    static func splitProperty(_ line: String) -> (key: String, value: String) {
        // Find the first colon that's not inside parameters
        // Parameters use semicolons; the value follows the first colon after all params
        guard let colonRange = line.range(of: ":") else {
            return (line, "")
        }
        let key = String(line[line.startIndex..<colonRange.lowerBound])
        let value = String(line[colonRange.upperBound...])
        return (key, value)
    }

    /// Extract an email from a "mailto:" URI.
    static func extractMailto(_ value: String) -> String? {
        let lower = value.lowercased()
        if let range = lower.range(of: "mailto:") {
            return String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Extract a parameter value from an iCalendar property key.
    static func extractParam(_ key: String, param: String) -> String? {
        let components = key.components(separatedBy: ";")
        for component in components {
            if component.hasPrefix("\(param)=") {
                var value = String(component.dropFirst(param.count + 1))
                // Remove quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                return value
            }
        }
        return nil
    }

    /// Parse a TRIGGER duration into minutes.
    static func parseTriggerMinutes(_ trigger: String) -> Int? {
        // Format: -PT15M, -PT1H, -P1D, etc.
        var str = trigger
        let negative = str.hasPrefix("-")
        if negative { str = String(str.dropFirst()) }
        if str.hasPrefix("P") { str = String(str.dropFirst()) }

        var totalMinutes = 0
        var numberStr = ""

        for ch in str {
            if ch.isNumber {
                numberStr += String(ch)
            } else {
                guard let num = Int(numberStr) else {
                    numberStr = ""
                    continue
                }
                switch ch {
                case "W": totalMinutes += num * 7 * 24 * 60
                case "D": totalMinutes += num * 24 * 60
                case "T": break // time designator, skip
                case "H": totalMinutes += num * 60
                case "M": totalMinutes += num
                case "S": totalMinutes += num / 60
                default: break
                }
                numberStr = ""
            }
        }

        return totalMinutes > 0 ? totalMinutes : nil
    }

    /// Escape special characters in iCalendar text values.
    static func escapeICalValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    /// Unescape iCalendar text values.
    static func unescapeICalValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - String Extension

extension String {
    /// Extract the local name from a potentially namespace-prefixed XML element name.
    var localXMLName: String {
        if let colonIndex = self.lastIndex(of: ":") {
            return String(self[self.index(after: colonIndex)...])
        }
        return self
    }

    /// Extract the last path component from a URL-like string.
    var lastPathComponent: String {
        let trimmed = self.hasSuffix("/") ? String(self.dropLast()) : self
        return trimmed.components(separatedBy: "/").last ?? self
    }
}
