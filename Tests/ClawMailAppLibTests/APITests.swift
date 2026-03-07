import Testing
import Foundation
import HTTPTypes
import NIOCore
import Darwin
@testable import ClawMailAppLib
@testable import ClawMailCore

/// Tests for REST API helper functions, HTTP status mapping, and rate limiting.

// MARK: - HTTP Status Mapping Tests

@Suite
struct HTTPStatusMappingTests {

    @Test func accountNotFoundReturns404() {
        #expect(httpStatus(for: .accountNotFound("test")) == .notFound)
    }

    @Test func messageNotFoundReturns404() {
        #expect(httpStatus(for: .messageNotFound("msg-1")) == .notFound)
    }

    @Test func folderNotFoundReturns404() {
        #expect(httpStatus(for: .folderNotFound("INBOX")) == .notFound)
    }

    @Test func authFailedReturns401() {
        #expect(httpStatus(for: .authFailed("bad creds")) == .unauthorized)
    }

    @Test func rateLimitExceededReturns429() {
        #expect(httpStatus(for: .rateLimitExceeded(retryAfterSeconds: 60)) == .tooManyRequests)
    }

    @Test func domainBlockedReturns403() {
        #expect(httpStatus(for: .domainBlocked("evil.com")) == .forbidden)
    }

    @Test func recipientPendingApprovalReturns409() {
        #expect(httpStatus(for: .recipientPendingApproval(emails: ["new@example.com"])) == .conflict)
    }

    @Test func invalidParameterReturns400() {
        #expect(httpStatus(for: .invalidParameter("bad param")) == .badRequest)
    }

    @Test func daemonNotRunningReturns503() {
        #expect(httpStatus(for: .daemonNotRunning) == .serviceUnavailable)
    }

    @Test func agentAlreadyConnectedReturns409() {
        #expect(httpStatus(for: .agentAlreadyConnected) == .conflict)
    }

    @Test func connectionErrorReturns502() {
        #expect(httpStatus(for: .connectionError("timeout")) == .badGateway)
    }

    @Test func serverErrorReturns500() {
        #expect(httpStatus(for: .serverError("oops")) == .internalServerError)
    }

    @Test func calendarNotAvailableReturns404() {
        #expect(httpStatus(for: .calendarNotAvailable) == .notFound)
    }

    @Test func contactsNotAvailableReturns404() {
        #expect(httpStatus(for: .contactsNotAvailable) == .notFound)
    }

    @Test func tasksNotAvailableReturns404() {
        #expect(httpStatus(for: .tasksNotAvailable) == .notFound)
    }

    @Test func accountDisconnectedReturns503() {
        #expect(httpStatus(for: .accountDisconnected("Gmail")) == .serviceUnavailable)
    }
}

// MARK: - JSON Response Builder Tests

@Suite
struct ResponseBuilderTests {

    @Test func jsonResponseSetsContentTypeJSON() {
        let response = jsonResponse(["key": "value"])
        #expect(response.headers[.contentType] == "application/json")
    }

    @Test func jsonResponseDefaultsTo200() {
        let response = jsonResponse(["ok": true])
        #expect(response.status == .ok)
    }

    @Test func jsonResponseUsesCustomStatus() {
        let response = jsonResponse(["created": true], status: .created)
        #expect(response.status == .created)
    }

    @Test func clawMailErrorResponseSetsCorrectStatus() {
        let response = clawMailErrorResponse(.accountNotFound("test"))
        #expect(response.status == .notFound)
        #expect(response.headers[.contentType] == "application/json")
    }

    @Test func rateLimitErrorResponseIncludesRetryAfter() {
        let response = clawMailErrorResponse(.rateLimitExceeded(retryAfterSeconds: 30))
        #expect(response.status == .tooManyRequests)
        let retryValue = response.headers[HTTPField.Name("Retry-After")!]
        #expect(retryValue != nil)
    }

    @Test func badRequestResponseReturns400() {
        let response = badRequestResponse("Missing parameter")
        #expect(response.status == .badRequest)
    }

    @Test func internalErrorResponseReturns500() {
        let response = internalErrorResponse("Something broke")
        #expect(response.status == .internalServerError)
    }

    @Test func genericErrorResponseHandlesClawMailError() {
        let response = genericErrorResponse(ClawMailError.authFailed("expired") as any Error)
        #expect(response.status == .unauthorized)
    }

    @Test func genericErrorResponseHandlesUnknownError() {
        struct TestError: Error {}
        let response = genericErrorResponse(TestError())
        #expect(response.status == .internalServerError)
    }
}

// MARK: - JSON Encoder/Decoder Config Tests

@Suite
struct JSONConfigTests {

    @Test func apiJSONEncoderUsesISO8601Dates() throws {
        let encoder = apiJSONEncoder()
        let date = Date(timeIntervalSince1970: 0) // 1970-01-01T00:00:00Z
        struct DateWrapper: Codable { let d: Date }
        let data = try encoder.encode(DateWrapper(d: date))
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("1970-01-01"))
    }

    @Test func apiJSONEncoderSortsKeys() throws {
        let encoder = apiJSONEncoder()
        struct KV: Codable { let z: Int; let a: Int }
        let data = try encoder.encode(KV(z: 1, a: 2))
        let json = String(data: data, encoding: .utf8)!
        let aIndex = json.range(of: "\"a\"")!.lowerBound
        let zIndex = json.range(of: "\"z\"")!.lowerBound
        #expect(aIndex < zIndex, "Keys should be sorted alphabetically")
    }

    @Test func apiJSONDecoderUsesISO8601Dates() throws {
        let decoder = apiJSONDecoder()
        struct DateWrapper: Codable { let d: Date }
        let json = "{\"d\":\"1970-01-01T00:00:00Z\"}"
        let wrapper = try decoder.decode(DateWrapper.self, from: Data(json.utf8))
        #expect(wrapper.d.timeIntervalSince1970 == 0)
    }
}

// MARK: - StatusRoutes Types Tests

@Suite
struct StatusRoutesTypesTests {

    @Test func daemonStatusEncodesCorrectly() throws {
        let status = DaemonStatus(
            status: "running",
            version: "1.0.0",
            agentConnected: true,
            uptime: 3600.0
        )
        let data = try apiJSONEncoder().encode(status)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"status\":\"running\""))
        #expect(json.contains("\"version\":\"1.0.0\""))
        #expect(json.contains("\"agentConnected\":true"))
    }

    @Test func accountSummaryEncodesFromAccount() throws {
        let account = Account(
            label: "Gmail",
            emailAddress: "test@gmail.com",
            displayName: "Test User",
            imapHost: "imap.gmail.com",
            imapPort: 993,
            smtpHost: "smtp.gmail.com",
            smtpPort: 465
        )
        let summary = AccountSummary(from: account)
        #expect(summary.label == "Gmail")
        #expect(summary.emailAddress == "test@gmail.com")
        #expect(summary.displayName == "Test User")
        #expect(summary.isEnabled == true)
        #expect(summary.hasCalDAV == false)
        #expect(summary.hasCardDAV == false)
    }
}

// MARK: - APIServer Lifecycle Tests

@Suite
struct APIServerLifecycleTests {

    @Test func apiServerStartsAndServesStatusRoute() async throws {
        let port = try findFreePort()
        let orchestrator = try AccountOrchestrator(
            config: AppConfig(restApiPort: port),
            databaseManager: try DatabaseManager(inMemory: true)
        )
        let server = APIServer(orchestrator: orchestrator, port: port)

        try await server.start()
        do {
            let url = URL(string: "http://127.0.0.1:\(port)/api/v1/status")!
            let (data, response) = try await URLSession.shared.data(from: url)

            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 200)

            let body = try #require(String(data: data, encoding: .utf8))
            #expect(body.contains("\"status\":\"running\""))
        } catch {
            await server.stop()
            throw error
        }
        await server.stop()
    }

    private func findFreePort() throws -> Int {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #expect(fd >= 0)
        defer { _ = Darwin.close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(.EADDRNOTAVAIL)
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.getsockname(fd, socketAddress, &length)
            }
        }
        guard nameResult == 0 else {
            throw POSIXError(.EADDRNOTAVAIL)
        }

        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }
}
