import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import ClawMailCore

@Suite(.serialized)
struct DAVSecurityTests {

    @Test func calDAVRejectsPlaintextBaseURL() throws {
        do {
            _ = try CalDAVClient(
                baseURL: URL(string: "http://calendar.example.com/dav")!,
                credential: .password(username: "user", password: "pass")
            )
            Issue.record("Expected CalDAV client init to reject plaintext HTTP")
        } catch let error as ClawMailError {
            #expect(error.message.contains("CalDAV URL must use HTTPS"))
        }
    }

    @Test func cardDAVRejectsPlaintextBaseURL() throws {
        do {
            _ = try CardDAVClient(
                baseURL: URL(string: "http://contacts.example.com/dav")!,
                credential: .password(username: "user", password: "pass")
            )
            Issue.record("Expected CardDAV client init to reject plaintext HTTP")
        } catch let error as ClawMailError {
            #expect(error.message.contains("CardDAV URL must use HTTPS"))
        }
    }

    @Test func calDAVRejectsCrossOriginPrincipalURL() async throws {
        let session = makeSession()
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "calendar.example.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "https://attacker.example.com/principals/evil/"
                )
            )
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://calendar.example.com/dav")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        do {
            try await client.authenticate()
            Issue.record("Expected cross-origin principal URL to fail authentication")
        } catch let error as ClawMailError {
            #expect(error.message.contains("cross-origin"))
        }

        let requests = MockDAVURLProtocol.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests.allSatisfy { $0.url?.host == "calendar.example.com" })
    }

    @Test func cardDAVRejectsCrossOriginHomeSetURL() async throws {
        let session = makeSession()
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "contacts.example.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/principals/user/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "contacts.example.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") != nil)
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "addressbook-home-set",
                    href: "https://attacker.example.com/addressbooks/evil/"
                )
            )
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://contacts.example.com/dav")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        do {
            try await client.authenticate()
            Issue.record("Expected cross-origin addressbook-home-set to fail authentication")
        } catch let error as ClawMailError {
            #expect(error.message.contains("cross-origin"))
        }

        let requests = MockDAVURLProtocol.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "contacts.example.com" })
    }

    @Test("CardDAV auth failure includes JSON error detail", .disabled(if: ProcessInfo.processInfo.environment["CI"] == "true", "Mock protocol timing issues in CI"))
func cardDAVAuthFailureIncludesJSONErrorDetailAndRequiredScope() async throws {
        let session = makeSession()
        // First request: resolveWellKnownIfNeeded (PROPFIND on .well-known)
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.path == "/.well-known/carddav")
            return self.response(
                url: request.url!,
                status: 403,
                headers: [
                    "Content-Type": "application/json; charset=UTF-8",
                    "WWW-Authenticate": #"Bearer realm="https://accounts.google.com/", error="insufficient_scope", scope="https://www.googleapis.com/auth/carddav""#,
                ],
                body: """
                {"error":{"message":"Request had insufficient authentication scopes."}}
                """
            )
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://www.googleapis.com/.well-known/carddav")!,
            credential: .oauthToken(.constant("access-token")),
            session: session
        )

        do {
            try await client.authenticate()
            Issue.record("Expected CardDAV authentication to fail")
        } catch let error as ClawMailError {
            #expect(error.message.contains("insufficient authentication scopes"))
            #expect(error.message.contains("https://www.googleapis.com/auth/carddav"))
        }
    }

    @Test func calDAVRejectsCrossOriginCalendarHrefDuringListing() async throws {
        let session = makeSession()
        MockDAVURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/principals/user/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "calendar-home-set",
                    href: "/calendars/user/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                  <d:response>
                    <d:href>https://attacker.example.com/calendars/evil/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Compromised</d:displayname>
                        <d:resourcetype>
                          <d:collection/>
                          <c:calendar/>
                        </d:resourcetype>
                        <c:supported-calendar-component-set>
                          <c:comp name="VEVENT"/>
                        </c:supported-calendar-component-set>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                </d:multistatus>
                """
            )
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://calendar.example.com/dav")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        do {
            _ = try await client.listCalendars()
            Issue.record("Expected cross-origin calendar href to be rejected")
        } catch let error as ClawMailError {
            #expect(error.message.contains("cross-origin"))
        }

        let requests = MockDAVURLProtocol.recordedRequests()
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.url?.host == "calendar.example.com" })
    }

    @Test func calDAVAcceptsHomeSetOnRedirectedEffectiveOrigin() async throws {
        let session = makeSession()
        let redirectedPrincipalURL = URL(string: "https://p42-caldav.icloud.com/123456/principal/")!
        let redirectedHomeURL = URL(string: "https://p42-caldav.icloud.com/123456/calendars/")!

        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "caldav.icloud.com")
            return self.response(
                url: redirectedPrincipalURL,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/123456/principal/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-caldav.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "calendar-home-set",
                    href: redirectedHomeURL.absoluteString
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-caldav.icloud.com")
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                  <d:response>
                    <d:href>/123456/calendars/work/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Work</d:displayname>
                        <d:resourcetype>
                          <d:collection/>
                          <c:calendar/>
                        </d:resourcetype>
                        <c:supported-calendar-component-set>
                          <c:comp name="VEVENT"/>
                        </c:supported-calendar-component-set>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                </d:multistatus>
                """
            )
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://caldav.icloud.com")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        let calendars = try await client.listCalendars()
        #expect(calendars.count == 1)
        #expect(calendars.first?.href == "/123456/calendars/work")

        let requestHosts = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.host }
        #expect(requestHosts == ["caldav.icloud.com", "p42-caldav.icloud.com", "p42-caldav.icloud.com"])
    }

    @Test func cardDAVAcceptsHomeSetOnRedirectedEffectiveOrigin() async throws {
        let session = makeSession()
        let redirectedPrincipalURL = URL(string: "https://p42-contacts.icloud.com/123456/principal/")!
        let redirectedHomeURL = URL(string: "https://p42-contacts.icloud.com/123456/addressbooks/")!

        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "contacts.icloud.com")
            return self.response(
                url: redirectedPrincipalURL,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/123456/principal/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-contacts.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "addressbook-home-set",
                    href: redirectedHomeURL.absoluteString
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-contacts.icloud.com")
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:">
                  <d:response>
                    <d:href>/123456/addressbooks/default/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Default</d:displayname>
                        <d:resourcetype>
                          <d:collection/>
                          <card:addressbook xmlns:card="urn:ietf:params:xml:ns:carddav"/>
                        </d:resourcetype>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                </d:multistatus>
                """
            )
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://contacts.icloud.com")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        let books = try await client.listAddressBooks()
        #expect(books.count == 1)
        #expect(books.first?.href == "/123456/addressbooks/default")

        let requestHosts = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.host }
        #expect(requestHosts == ["contacts.icloud.com", "p42-contacts.icloud.com", "p42-contacts.icloud.com"])
    }

    @Test("CardDAV preserves authenticated PROPFIND across redirects", .disabled(if: ProcessInfo.processInfo.environment["CI"] == "true", "Mock protocol timing issues in CI"))
    func cardDAVPreservesAuthenticatedPropfindAcrossRedirects() async throws {
        let session = makeSession()
        let redirectedURL = URL(string: "https://apidata.googleusercontent.com/carddav/v1/principals/user/lists/default/")!
        let redirectedPrincipalURL = URL(string: "https://apidata.googleusercontent.com/carddav/v1/principals/user/")!

        // First: resolveWellKnownIfNeeded follows redirect
        MockDAVURLProtocol.enqueueRedirect { request in
            #expect(request.url?.absoluteString == "https://www.googleapis.com/.well-known/carddav")
            #expect(request.httpMethod == "PROPFIND")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dav-token")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 301,
                httpVersion: nil,
                headerFields: ["Location": redirectedURL.absoluteString]
            )!
            var redirectedRequest = URLRequest(url: redirectedURL)
            redirectedRequest.httpMethod = "GET"
            return (response, redirectedRequest)
        }
        // Second: authenticate() PROPFIND on redirected URL
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url == redirectedURL)
            #expect(request.httpMethod == "PROPFIND")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dav-token")
            #expect(request.value(forHTTPHeaderField: "Depth") == "0")
            return self.response(
                url: redirectedURL,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: redirectedPrincipalURL.path
                )
            )
        }
        // Third: discoverAddressBookHome
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == redirectedPrincipalURL.host)
            #expect(request.url?.path == redirectedPrincipalURL.path)
            #expect(request.httpMethod == "PROPFIND")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dav-token")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "addressbook-home-set",
                    href: "/carddav/v1/principals/user/lists/default/"
                )
            )
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://www.googleapis.com/.well-known/carddav")!,
            credential: .oauthToken(OAuthTokenProvider { "dav-token" }),
            session: session
        )

        try await client.authenticate()

        let requestHosts = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.host }
        #expect(requestHosts == ["www.googleapis.com", "apidata.googleusercontent.com", "apidata.googleusercontent.com"])
    }

    @Test("CardDAV falls back when Google address book redirect rejects principal PROPFIND", .disabled(if: ProcessInfo.processInfo.environment["CI"] == "true", "Mock protocol timing issues in CI"))
    func cardDAVFallsBackWhenGoogleAddressBookRedirectRejectsPrincipalPropfind() async throws {
        let session = makeSession()
        let redirectedURL = URL(string: "https://www.googleapis.com/carddav/v1/principals/user@example.com/lists/default/")!
        let redirectedURLWithoutTrailingSlash = URL(string: "https://www.googleapis.com/carddav/v1/principals/user@example.com/lists/default")!
        let expectedNormalizedURL = normalizedTrailingSlash(redirectedURL.absoluteString)

        // First: resolveWellKnownIfNeeded follows redirect
        MockDAVURLProtocol.enqueueRedirect { request in
            #expect(request.url?.absoluteString == "https://www.googleapis.com/.well-known/carddav")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 301,
                httpVersion: nil,
                headerFields: ["Location": redirectedURL.absoluteString]
            )!
            return (response, URLRequest(url: redirectedURL))
        }
        // Second: authenticate() PROPFIND gets 400, triggering fallback
        MockDAVURLProtocol.enqueue { request in
            #expect(normalizedTrailingSlash(request.url?.absoluteString) == expectedNormalizedURL)
            return self.response(
                url: request.url!,
                status: 400,
                headers: ["Content-Type": "application/json; charset=UTF-8"],
                body: """
                {"error":{"message":"Invalid request for current-user-principal at address book resource."}}
                """
            )
        }
        // Third: authenticateViaGoogleAddressBookFallback PROPFIND
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url == redirectedURL || request.url == redirectedURLWithoutTrailingSlash)
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
                  <d:response>
                    <d:href>/carddav/v1/principals/user@example.com/lists/default/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Default</d:displayname>
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
            )
        }
        // Fourth: listAddressBooks PROPFIND
        MockDAVURLProtocol.enqueue { request in
            #expect(normalizedTrailingSlash(request.url?.absoluteString) == expectedNormalizedURL)
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:" xmlns:card="urn:ietf:params:xml:ns:carddav">
                  <d:response>
                    <d:href>/carddav/v1/principals/user@example.com/lists/default/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Default</d:displayname>
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
            )
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://www.googleapis.com/.well-known/carddav")!,
            credential: .oauthToken(OAuthTokenProvider { "dav-token" }),
            session: session
        )

        try await client.authenticate()
        let books = try await client.listAddressBooks()
        #expect(books.count == 1)
        #expect(books.first?.displayName == "Default")

        let requestURLs = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.absoluteString }
        #expect(requestURLs.map(normalizedTrailingSlash) == [
            "https://www.googleapis.com/.well-known/carddav",
            expectedNormalizedURL,
            expectedNormalizedURL,
            expectedNormalizedURL,
        ])
    }

    @Test func calDAVAcceptsAppleShardHomeSetWithoutHTTPRedirect() async throws {
        let session = makeSession()

        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "caldav.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/123456/principal/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "caldav.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "calendar-home-set",
                    href: "https://p42-caldav.icloud.com/123456/calendars/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-caldav.icloud.com")
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                  <d:response>
                    <d:href>/123456/calendars/work/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Work</d:displayname>
                        <d:resourcetype>
                          <d:collection/>
                          <c:calendar/>
                        </d:resourcetype>
                        <c:supported-calendar-component-set>
                          <c:comp name="VEVENT"/>
                        </c:supported-calendar-component-set>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                </d:multistatus>
                """
            )
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://caldav.icloud.com")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        let calendars = try await client.listCalendars()
        #expect(calendars.count == 1)

        let requestHosts = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.host }
        #expect(requestHosts == ["caldav.icloud.com", "caldav.icloud.com", "p42-caldav.icloud.com"])
    }

    @Test func cardDAVAcceptsAppleShardHomeSetWithoutHTTPRedirect() async throws {
        let session = makeSession()

        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "contacts.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/123456/principal/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "contacts.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "addressbook-home-set",
                    href: "https://p42-contacts.icloud.com/123456/addressbooks/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-contacts.icloud.com")
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:">
                  <d:response>
                    <d:href>/123456/addressbooks/default/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Default</d:displayname>
                        <d:resourcetype>
                          <d:collection/>
                          <card:addressbook xmlns:card="urn:ietf:params:xml:ns:carddav"/>
                        </d:resourcetype>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                </d:multistatus>
                """
            )
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://contacts.icloud.com")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        let books = try await client.listAddressBooks()
        #expect(books.count == 1)

        let requestHosts = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.host }
        #expect(requestHosts == ["contacts.icloud.com", "contacts.icloud.com", "p42-contacts.icloud.com"])
    }

    @Test func calDAVAcceptsAppleCalendarWSHomeSetWithoutHTTPRedirect() async throws {
        let session = makeSession()

        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "caldav.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/123456/principal/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "caldav.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "calendar-home-set",
                    href: "https://p42-calendarws.icloud.com/123456/calendars/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-calendarws.icloud.com")
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
                  <d:response>
                    <d:href>/123456/calendars/work/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Work</d:displayname>
                        <d:resourcetype>
                          <d:collection/>
                          <c:calendar/>
                        </d:resourcetype>
                        <c:supported-calendar-component-set>
                          <c:comp name="VEVENT"/>
                        </c:supported-calendar-component-set>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                </d:multistatus>
                """
            )
        }

        let client = try CalDAVClient(
            baseURL: URL(string: "https://caldav.icloud.com")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        let calendars = try await client.listCalendars()
        #expect(calendars.count == 1)

        let requestHosts = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.host }
        #expect(requestHosts == ["caldav.icloud.com", "caldav.icloud.com", "p42-calendarws.icloud.com"])
    }

    @Test func cardDAVAcceptsAppleContactsWSHomeSetWithoutHTTPRedirect() async throws {
        let session = makeSession()

        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "contacts.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "current-user-principal",
                    href: "/123456/principal/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "contacts.icloud.com")
            return self.response(
                url: request.url!,
                body: self.multistatusBody(
                    property: "addressbook-home-set",
                    href: "https://p42-contactsws.icloud.com/123456/addressbooks/"
                )
            )
        }
        MockDAVURLProtocol.enqueue { request in
            #expect(request.url?.host == "p42-contactsws.icloud.com")
            return self.response(
                url: request.url!,
                body: """
                <?xml version="1.0" encoding="UTF-8"?>
                <d:multistatus xmlns:d="DAV:">
                  <d:response>
                    <d:href>/123456/addressbooks/default/</d:href>
                    <d:propstat>
                      <d:prop>
                        <d:displayname>Default</d:displayname>
                        <d:resourcetype>
                          <d:collection/>
                          <card:addressbook xmlns:card="urn:ietf:params:xml:ns:carddav"/>
                        </d:resourcetype>
                      </d:prop>
                      <d:status>HTTP/1.1 200 OK</d:status>
                    </d:propstat>
                  </d:response>
                </d:multistatus>
                """
            )
        }

        let client = try CardDAVClient(
            baseURL: URL(string: "https://contacts.icloud.com")!,
            credential: .password(username: "user", password: "pass"),
            session: session
        )

        let books = try await client.listAddressBooks()
        #expect(books.count == 1)

        let requestHosts = MockDAVURLProtocol.recordedRequests().compactMap { $0.url?.host }
        #expect(requestHosts == ["contacts.icloud.com", "contacts.icloud.com", "p42-contactsws.icloud.com"])
    }

    private func makeSession() -> URLSession {
        MockDAVURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDAVURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(url: URL, status: Int = 207, headers: [String: String]? = nil, body: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!,
            Data(body.utf8)
        )
    }

    private func multistatusBody(property: String, href: String) -> String {
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

    private func normalizedTrailingSlash(_ string: String?) -> String {
        guard let string else { return "<nil>" }
        if string.hasSuffix("/") {
            return String(string.dropLast())
        }
        return string
    }
}

private final class MockDAVURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [@Sendable (URLRequest, URLProtocol) throws -> Void] = []
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
        handlers.append { request, proto in
            let (response, data) = try handler(request)
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }

    static func enqueueRedirect(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, URLRequest)
    ) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append { request, proto in
            let (response, redirectedRequest) = try handler(request)
            proto.client?.urlProtocol(proto, wasRedirectedTo: redirectedRequest, redirectResponse: response)
        }
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
        let handler: (@Sendable (URLRequest, URLProtocol) throws -> Void)?
        Self.lock.lock()
        Self.requests.append(request)
        handler = Self.handlers.isEmpty ? nil : Self.handlers.removeFirst()
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: ClawMailError.serverError("No mock response configured"))
            return
        }

        do {
            try handler(request, self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
