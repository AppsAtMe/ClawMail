import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - CardDAV Data Types

/// Represents an address book discovered via CardDAV PROPFIND.
public struct CardDAVAddressBook: Codable, Sendable, Equatable {
    public var href: String
    public var displayName: String

    public init(href: String, displayName: String) {
        self.href = href
        self.displayName = displayName
    }
}

struct CardDAVResource: Sendable, Equatable {
    var href: String
    var addressData: String
}

/// Credential used for CardDAV authentication.
public enum CardDAVCredential: Sendable {
    case password(username: String, password: String)
    case oauthToken(OAuthTokenProvider)
}

// MARK: - CardDAVClient

/// Actor-based CardDAV client using URLSession for HTTP.
///
/// CardDAV is a WebDAV extension over HTTP that uses XML for requests/responses
/// and vCard (RFC 6350) for contact payloads.
public actor CardDAVClient {

    // MARK: - Properties

    private let credential: CardDAVCredential
    private let session: URLSession
    private var serverURL: URL
    private var addressBookHomePath: String?

    // MARK: - Initialization

    public init(baseURL: URL, credential: CardDAVCredential, session: URLSession? = nil) throws {
        let validatedBaseURL = try DAVURLValidator.validateConfiguredURL(baseURL, serviceName: "CardDAV")
        self.credential = credential
        self.session = session ?? URLSession.shared
        self.serverURL = validatedBaseURL
    }

    // MARK: - Discovery

    /// Attempt auto-discovery of CardDAV endpoint from an email address.
    public func discover(from email: String) async throws -> URL? {
        let domain = email.components(separatedBy: "@").last ?? ""
        guard !domain.isEmpty else { return nil }

        let wellKnownURLs = [
            URL(string: "https://\(domain)/.well-known/carddav"),
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
                let (_, response) = try await send(request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...399).contains(httpResponse.statusCode) {
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

    /// Test authentication by performing a PROPFIND on the base URL.
    public func authenticate() async throws {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = CardDAVXMLBuilder.propfind(properties: ["d:current-user-principal"])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await send(request)
        try updateServerURL(from: response)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawMailError.connectionError("Invalid response from CardDAV server")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClawMailError.authFailed(
                authFailureMessage(
                    context: "authentication",
                    statusCode: httpResponse.statusCode,
                    data: data
                )
            )
        }

        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 else {
            throw ClawMailError.connectionError("CardDAV server returned HTTP \(httpResponse.statusCode)")
        }

        // Try to extract current-user-principal for later use
        let parsed = CardDAVResponseParser.parse(data: data)
        if let principal = parsed.first?.properties["current-user-principal"] {
            try await discoverAddressBookHome(principalPath: principal)
        }
    }

    // MARK: - Address Book Operations

    /// List all address books from the addressbook-home-set.
    public func listAddressBooks() async throws -> [CardDAVAddressBook] {
        let homeURL = try await resolveAddressBookHomeURL()

        var request = URLRequest(url: homeURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = CardDAVXMLBuilder.propfind(properties: [
            "d:displayname",
            "d:resourcetype",
        ])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await send(request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "listAddressBooks", data: data)

        let responses = CardDAVResponseParser.parse(data: data)
        var books: [CardDAVAddressBook] = []

        for item in responses {
            guard item.isAddressBookCollection else { continue }
            let hrefURL = try resolveServerURL(item.href, context: "listAddressBooks href")
            let book = CardDAVAddressBook(
                href: hrefURL.path,
                displayName: item.properties["displayname"] ?? item.href.lastPathComponent
            )
            books.append(book)
        }

        return books
    }

    /// Retrieve contacts from an address book, optionally filtered by a text query.
    /// Returns raw vCard strings.
    public func getContacts(addressBook: String, query: String? = nil) async throws -> [String] {
        let bookURL = try resolveServerURL(addressBook, context: "getContacts address book")

        var request = URLRequest(url: bookURL)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body: String
        if let query = query, !query.isEmpty {
            body = CardDAVXMLBuilder.addressbookQuery(textFilter: query)
        } else {
            body = CardDAVXMLBuilder.addressbookMultiget()
        }
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await send(request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "getContacts", data: data)

        let responses = CardDAVResponseParser.parse(data: data)
        return responses.compactMap { $0.addressData }
    }

    func findContact(addressBook: String, uid: String) async throws -> CardDAVResource? {
        let bookURL = try resolveServerURL(addressBook, context: "findContact address book")

        var request = URLRequest(url: bookURL)
        request.httpMethod = "REPORT"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)
        request.httpBody = CardDAVXMLBuilder.addressbookUIDQuery(uid: uid).data(using: .utf8)

        let (data, response) = try await send(request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "findContact", data: data)

        let responses = CardDAVResponseParser.parse(data: data)
        for item in responses {
            guard let addressData = item.addressData else { continue }
            let hrefURL = try resolveServerURL(item.href, context: "findContact href")
            return CardDAVResource(href: hrefURL.path, addressData: addressData)
        }

        return nil
    }

    /// Create a new contact. Returns the href of the created resource.
    public func createContact(addressBook: String, vcard: String) async throws -> String {
        let uid = VCardParser.extractUID(from: vcard) ?? UUID().uuidString
        let resourcePath = addressBook.hasSuffix("/") ? "\(addressBook)\(uid).vcf" : "\(addressBook)/\(uid).vcf"
        let resourceURL = try resolveServerURL(resourcePath, context: "createContact resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "PUT"
        request.setValue("text/vcard; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        try await applyAuth(to: &request)
        request.httpBody = vcard.data(using: .utf8)

        let (_, response) = try await send(request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "createContact", allowedCodes: [201, 204])

        return resourcePath
    }

    /// Update an existing contact.
    public func updateContact(addressBook: String, uid: String, vcard: String) async throws {
        let resourcePath = addressBook.hasSuffix("/") ? "\(addressBook)\(uid).vcf" : "\(addressBook)/\(uid).vcf"
        try await updateContact(resourceHref: resourcePath, vcard: vcard)
    }

    func updateContact(resourceHref: String, vcard: String) async throws {
        let resourceURL = try resolveServerURL(resourceHref, context: "updateContact resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "PUT"
        request.setValue("text/vcard; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)
        request.httpBody = vcard.data(using: .utf8)

        let (_, response) = try await send(request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "updateContact", allowedCodes: [200, 201, 204])
    }

    /// Delete a contact by UID.
    public func deleteContact(addressBook: String, uid: String) async throws {
        let resourcePath = addressBook.hasSuffix("/") ? "\(addressBook)\(uid).vcf" : "\(addressBook)/\(uid).vcf"
        try await deleteContact(resourceHref: resourcePath)
    }

    func deleteContact(resourceHref: String) async throws {
        let resourceURL = try resolveServerURL(resourceHref, context: "deleteContact resource")

        var request = URLRequest(url: resourceURL)
        request.httpMethod = "DELETE"
        try await applyAuth(to: &request)

        let (_, response) = try await send(request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "deleteContact", allowedCodes: [200, 204])
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
        data: Data? = nil,
        allowedCodes: Set<Int> = [200, 207]
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawMailError.connectionError("\(context): Invalid response")
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClawMailError.authFailed(
                authFailureMessage(
                    context: context,
                    statusCode: httpResponse.statusCode,
                    data: data
                )
            )
        }
        guard allowedCodes.contains(httpResponse.statusCode) else {
            throw ClawMailError.serverError("CardDAV \(context): HTTP \(httpResponse.statusCode)")
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(
            for: request,
            delegate: DAVRedirectPreservingDelegate(serviceName: "CardDAV", templateRequest: request)
        )
    }

    private func updateServerURL(from response: URLResponse) throws {
        guard let effectiveURL = response.url else { return }
        serverURL = try DAVURLValidator.validateConfiguredURL(effectiveURL, serviceName: "CardDAV")
    }

    private func discoverAddressBookHome(principalPath: String) async throws {
        let principalURL = try resolveServerURL(principalPath, context: "discoverAddressBookHome principal")

        var request = URLRequest(url: principalURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        try await applyAuth(to: &request)

        let body = CardDAVXMLBuilder.propfind(properties: ["card:addressbook-home-set"])
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await send(request)
        try updateServerURL(from: response)
        try validateResponse(response, context: "discoverAddressBookHome", data: data)
        let responses = CardDAVResponseParser.parse(data: data)
        if let home = responses.first?.properties["addressbook-home-set"] {
            let homeURL = try resolveServerURL(home, context: "discoverAddressBookHome home-set")
            self.addressBookHomePath = storedServerReference(for: homeURL)
        }
    }

    private func resolveAddressBookHomeURL() async throws -> URL {
        if let home = addressBookHomePath {
            return try resolveServerURL(home, context: "resolveAddressBookHome")
        }
        try await authenticate()
        return try resolveServerURL(addressBookHomePath ?? serverURL.path, context: "resolveAddressBookHome")
    }

    private func resolveServerURL(_ path: String, context: String) throws -> URL {
        try DAVURLValidator.resolveServerURL(
            path,
            relativeTo: serverURL,
            serviceName: "CardDAV",
            context: context
        )
    }

    private func storedServerReference(for url: URL) -> String {
        if url.host?.lowercased() != serverURL.host?.lowercased() {
            return url.absoluteString
        }
        return url.path
    }

    private func authFailureMessage(context: String, statusCode: Int, data: Data?) -> String {
        if let detail = extractErrorDetail(from: data) {
            return "CardDAV \(context): Authentication failed (HTTP \(statusCode)): \(detail)"
        }
        return "CardDAV \(context): Authentication failed (HTTP \(statusCode))"
    }

    private func extractErrorDetail(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = jsonObject["error"] as? [String: Any] {
                if let message = error["message"] as? String {
                    return sanitizedErrorDetail(message)
                }
                if let description = error["error_description"] as? String {
                    return sanitizedErrorDetail(description)
                }
            }
            if let message = jsonObject["error_description"] as? String {
                return sanitizedErrorDetail(message)
            }
            if let message = jsonObject["message"] as? String {
                return sanitizedErrorDetail(message)
            }
        }

        if let raw = String(data: data, encoding: .utf8) {
            return sanitizedErrorDetail(raw)
        }
        return nil
    }

    private func sanitizedErrorDetail(_ raw: String) -> String? {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > 160 ? String(collapsed.prefix(157)) + "..." : collapsed
    }
}

private final class DAVRedirectPreservingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let serviceName: String
    private let templateRequest: URLRequest

    init(serviceName: String, templateRequest: URLRequest) {
        self.serviceName = serviceName
        self.templateRequest = templateRequest
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
              (try? DAVURLValidator.validateConfiguredURL(redirectedURL, serviceName: serviceName)) != nil else {
            completionHandler(nil)
            return
        }

        var redirectedRequest = request
        redirectedRequest.httpMethod = templateRequest.httpMethod
        redirectedRequest.httpBody = templateRequest.httpBody
        redirectedRequest.httpBodyStream = nil
        for (field, value) in templateRequest.allHTTPHeaderFields ?? [:] {
            redirectedRequest.setValue(value, forHTTPHeaderField: field)
        }

        completionHandler(redirectedRequest)
    }
}

// MARK: - CardDAV XML Builder

/// Builds XML bodies for CardDAV/WebDAV requests.
enum CardDAVXMLBuilder: Sendable {

    /// Build a PROPFIND XML body requesting specific properties.
    static func propfind(properties: [String]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav" xmlns:cs="http://calendarserver.org/ns/">
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

    /// Build a REPORT body for an addressbook-query with text filter.
    static func addressbookQuery(textFilter: String) -> String {
        // Escape XML special characters in the filter text
        let escapedFilter = textFilter
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop>
            <d:getetag/>
            <card:address-data/>
          </d:prop>
          <card:filter>
            <card:prop-filter name="FN">
              <card:text-match collation="i;unicode-casemap" match-type="contains">\(escapedFilter)</card:text-match>
            </card:prop-filter>
          </card:filter>
        </card:addressbook-query>
        """
    }

    /// Build a REPORT body for addressbook-multiget (retrieve all contacts).
    static func addressbookMultiget() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop>
            <d:getetag/>
            <card:address-data/>
          </d:prop>
          <card:filter>
            <card:prop-filter name="FN">
              <card:is-not-defined/>
            </card:prop-filter>
          </card:filter>
        </card:addressbook-query>
        """
    }

    static func addressbookUIDQuery(uid: String) -> String {
        let escapedUID = xmlEscape(uid)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <card:addressbook-query xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
          <d:prop>
            <d:getetag/>
            <card:address-data/>
          </d:prop>
          <card:filter>
            <card:prop-filter name="UID">
              <card:text-match collation="i;unicode-casemap" match-type="equals">\(escapedUID)</card:text-match>
            </card:prop-filter>
          </card:filter>
        </card:addressbook-query>
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

// MARK: - CardDAV Response Parser

/// Parsed single response from a CardDAV multistatus response.
struct CardDAVResponseItem: Sendable {
    var href: String
    var statusCode: Int
    var properties: [String: String]
    var addressData: String?
    var isAddressBookCollection: Bool
}

/// Parses CardDAV multistatus XML responses.
enum CardDAVResponseParser: Sendable {

    static func parse(data: Data) -> [CardDAVResponseItem] {
        let parser = CardDAVXMLParserDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.items
    }
}

/// XMLParser delegate for CardDAV multistatus responses.
private final class CardDAVXMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    var items: [CardDAVResponseItem] = []
    private var currentItem: CardDAVResponseItem?
    private var currentElement: String = ""
    private var currentText: String = ""
    private var inResponse: Bool = false
    private var inPropStat: Bool = false
    private var inProp: Bool = false
    private var inAddressData: Bool = false

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
            currentItem = CardDAVResponseItem(
                href: "",
                statusCode: 200,
                properties: [:],
                addressData: nil,
                isAddressBookCollection: false
            )
        case "propstat":
            inPropStat = true
        case "prop":
            if inPropStat {
                inProp = true
            }
        case "address-data":
            inAddressData = true
        case "addressbook":
            if inProp {
                currentItem?.isAddressBookCollection = true
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
                currentItem?.properties["addressbook-home-set"] = trimmed
                currentItem?.properties["current-user-principal"] = trimmed
            } else if inResponse && currentItem != nil {
                currentItem?.href = trimmed
            }
        case "displayname":
            if inProp {
                currentItem?.properties["displayname"] = trimmed
            }
        case "address-data":
            if inProp {
                currentItem?.addressData = currentText
            }
            inAddressData = false
        default:
            if inProp && !trimmed.isEmpty {
                currentItem?.properties[localName] = trimmed
            }
        }

        currentText = ""
    }
}

// MARK: - vCard Parser

/// Parses and builds vCard (RFC 6350) formatted contact data.
///
/// Supports vCard 3.0 and 4.0 formats for the core contact properties
/// used by ClawMail: names, emails, phones, organization, title, notes.
public enum VCardParser: Sendable {

    // MARK: - Parsed Contact

    /// Structured representation of a parsed vCard.
    public struct ParsedContact: Sendable {
        public var uid: String
        public var formattedName: String?
        public var firstName: String?
        public var lastName: String?
        public var emails: [(type: String, address: String)]
        public var phones: [(type: String, number: String)]
        public var organization: String?
        public var title: String?
        public var notes: String?

        public init(
            uid: String = "",
            formattedName: String? = nil,
            firstName: String? = nil,
            lastName: String? = nil,
            emails: [(type: String, address: String)] = [],
            phones: [(type: String, number: String)] = [],
            organization: String? = nil,
            title: String? = nil,
            notes: String? = nil
        ) {
            self.uid = uid
            self.formattedName = formattedName
            self.firstName = firstName
            self.lastName = lastName
            self.emails = emails
            self.phones = phones
            self.organization = organization
            self.title = title
            self.notes = notes
        }
    }

    // MARK: - Parsing

    /// Parse a vCard string and extract contact information.
    public static func parseContacts(from vcard: String) -> [ParsedContact] {
        let unfolded = unfoldVCardLines(vcard)
        let lines = unfolded.components(separatedBy: "\n")

        var contacts: [ParsedContact] = []
        var current: ParsedContact?
        var inVCard = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.uppercased() == "BEGIN:VCARD" {
                inVCard = true
                current = ParsedContact()
                continue
            }
            if trimmed.uppercased() == "END:VCARD" {
                if let contact = current {
                    contacts.append(contact)
                }
                current = nil
                inVCard = false
                continue
            }

            guard inVCard else { continue }

            let (key, value) = splitVCardProperty(trimmed)
            let baseKey = key.components(separatedBy: ";").first?.uppercased() ?? key.uppercased()

            switch baseKey {
            case "UID":
                current?.uid = value
            case "FN":
                current?.formattedName = unescapeVCardValue(value)
            case "N":
                // N format: Last;First;Middle;Prefix;Suffix
                let parts = value.components(separatedBy: ";")
                if parts.count >= 1 {
                    current?.lastName = parts[0].isEmpty ? nil : unescapeVCardValue(parts[0])
                }
                if parts.count >= 2 {
                    current?.firstName = parts[1].isEmpty ? nil : unescapeVCardValue(parts[1])
                }
            case "EMAIL":
                let emailType = extractVCardType(from: key) ?? "other"
                current?.emails.append((type: emailType, address: value))
            case "TEL":
                let phoneType = extractVCardType(from: key) ?? "other"
                current?.phones.append((type: phoneType, number: value))
            case "ORG":
                // ORG can have multiple components separated by semicolons
                let orgParts = value.components(separatedBy: ";")
                current?.organization = unescapeVCardValue(orgParts.first ?? value)
            case "TITLE":
                current?.title = unescapeVCardValue(value)
            case "NOTE":
                current?.notes = unescapeVCardValue(value)
            default:
                break
            }
        }

        return contacts
    }

    /// Extract UID from raw vCard text.
    public static func extractUID(from vcard: String) -> String? {
        let unfolded = unfoldVCardLines(vcard)
        for line in unfolded.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("UID:") {
                return String(trimmed.dropFirst(4))
            }
        }
        return nil
    }

    // MARK: - Building

    /// Build a vCard 3.0 string from structured contact data.
    public static func buildVCard(
        uid: String,
        formattedName: String,
        firstName: String? = nil,
        lastName: String? = nil,
        emails: [(type: String, address: String)] = [],
        phones: [(type: String, number: String)] = [],
        organization: String? = nil,
        title: String? = nil,
        notes: String? = nil
    ) -> String {
        var lines: [String] = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "PRODID:-//ClawMail//CardDAV Client//EN",
            "UID:\(uid)",
            "FN:\(escapeVCardValue(formattedName))",
        ]

        // N property: Last;First;;;
        let last = lastName ?? ""
        let first = firstName ?? ""
        lines.append("N:\(escapeVCardValue(last));\(escapeVCardValue(first));;;")

        for email in emails {
            let typeStr = email.type.uppercased()
            lines.append("EMAIL;TYPE=\(typeStr):\(email.address)")
        }

        for phone in phones {
            let typeStr = phone.type.uppercased()
            lines.append("TEL;TYPE=\(typeStr):\(phone.number)")
        }

        if let organization = organization {
            lines.append("ORG:\(escapeVCardValue(organization))")
        }

        if let title = title {
            lines.append("TITLE:\(escapeVCardValue(title))")
        }

        if let notes = notes {
            lines.append("NOTE:\(escapeVCardValue(notes))")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        lines.append("REV:\(formatter.string(from: Date()))")

        lines.append("END:VCARD")

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Internal Helpers

    /// Unfold vCard line continuations.
    static func unfoldVCardLines(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\r\n ", with: "")
        result = result.replacingOccurrences(of: "\r\n\t", with: "")
        result = result.replacingOccurrences(of: "\n ", with: "")
        result = result.replacingOccurrences(of: "\n\t", with: "")
        return result
    }

    /// Split a vCard property line into key (with params) and value.
    static func splitVCardProperty(_ line: String) -> (key: String, value: String) {
        guard let colonRange = line.range(of: ":") else {
            return (line, "")
        }
        let key = String(line[line.startIndex..<colonRange.lowerBound])
        let value = String(line[colonRange.upperBound...])
        return (key, value)
    }

    /// Extract the TYPE parameter value from a vCard property key.
    static func extractVCardType(from key: String) -> String? {
        let parts = key.components(separatedBy: ";")
        for part in parts {
            let upper = part.uppercased()
            if upper.hasPrefix("TYPE=") {
                let typeValue = String(part.dropFirst(5))
                // Remove quotes if present
                let cleaned = typeValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                // Could have multiple types separated by commas; take the first
                return cleaned.components(separatedBy: ",").first?.lowercased()
            }
            // vCard 2.1 style: just the type name without TYPE=
            let knownTypes = ["WORK", "HOME", "CELL", "FAX", "PAGER", "VOICE", "OTHER"]
            if knownTypes.contains(upper) {
                return part.lowercased()
            }
        }
        return nil
    }

    /// Escape special characters in vCard text values.
    static func escapeVCardValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }

    /// Unescape vCard text values.
    static func unescapeVCardValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
