import Testing
import Foundation
@testable import ClawMailCore

/// Tests for logic extracted from executable targets into ClawMailCore for testability.
/// Covers: WebhookManager, OAuthHelpers, CLIParamBuilders, NotificationForwarder.

// MARK: - WebhookManager Tests

@Suite
struct WebhookManagerTests {

    // MARK: Init Validation

    @Test func initReturnsNilForNilURL() async {
        let manager = WebhookManager(urlString: nil)
        #expect(manager == nil)
    }

    @Test func initReturnsNilForEmptyString() async {
        let manager = WebhookManager(urlString: "")
        #expect(manager == nil)
    }

    @Test func initReturnsNilForInvalidURL() async {
        let manager = WebhookManager(urlString: "not a url %%%")
        #expect(manager == nil)
    }

    @Test func initReturnsNilForFileScheme() async {
        let manager = WebhookManager(urlString: "file:///etc/passwd")
        #expect(manager == nil)
    }

    @Test func initReturnsNilForFTPScheme() async {
        let manager = WebhookManager(urlString: "ftp://example.com/data")
        #expect(manager == nil)
    }

    @Test func initSucceedsForHTTP() async {
        let manager = WebhookManager(urlString: "http://example.com/webhook")
        #expect(manager != nil)
    }

    @Test func initSucceedsForHTTPS() async {
        let manager = WebhookManager(urlString: "https://example.com/webhook")
        #expect(manager != nil)
    }

    // MARK: SSRF Prevention

    @Test func blocksAWSMetadataEndpoint() async {
        let manager = WebhookManager(urlString: "http://169.254.169.254/latest/meta-data/")
        #expect(manager == nil)
    }

    @Test func blocksGoogleMetadataEndpoint() async {
        let manager = WebhookManager(urlString: "http://metadata.google.internal/computeMetadata/v1/")
        #expect(manager == nil)
    }

    @Test func blocksIPv6Loopback() async {
        let manager = WebhookManager(urlString: "http://[::1]/webhook")
        #expect(manager == nil)
    }

    @Test func blocksLocalhostIPv4() async {
        #expect(WebhookManager(urlString: "http://127.0.0.1:8080/webhook") == nil)
    }

    @Test func blocksLocalhostHostname() async {
        #expect(WebhookManager(urlString: "http://localhost:8080/webhook") == nil)
    }

    @Test func blocksWildcardAddress() async {
        #expect(WebhookManager(urlString: "http://0.0.0.0/webhook") == nil)
    }

    // MARK: Payload Encoding

    @Test func webhookPayloadEncodesCorrectly() throws {
        let payload = WebhookPayload(
            event: "new_email",
            timestamp: "2026-03-05T12:00:00Z",
            data: ["account": "Gmail", "folder": "INBOX"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"event\":\"new_email\""))
        #expect(json.contains("\"timestamp\":\"2026-03-05T12:00:00Z\""))
        #expect(json.contains("\"account\":\"Gmail\""))
        #expect(json.contains("\"folder\":\"INBOX\""))
    }

    @Test func webhookPayloadRoundTrips() throws {
        let payload = WebhookPayload(
            event: "test_event",
            timestamp: "2026-01-01T00:00:00Z",
            data: ["key": "value"]
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WebhookPayload.self, from: data)
        #expect(decoded.event == "test_event")
        #expect(decoded.timestamp == "2026-01-01T00:00:00Z")
        #expect(decoded.data["key"] == "value")
    }
}

// MARK: - OAuthHelpers Tests

@Suite
struct OAuthHelpersTests {

    // MARK: generateState

    @Test func generateStateProduces64HexChars() {
        let state = OAuthHelpers.generateState()
        #expect(state.count == 64)
        #expect(state.allSatisfy { $0.isHexDigit })
    }

    @Test func generateStateIsUnique() {
        let state1 = OAuthHelpers.generateState()
        let state2 = OAuthHelpers.generateState()
        #expect(state1 != state2)
    }

    // MARK: constantTimeEqual

    @Test func constantTimeEqualReturnsTrueForSameStrings() {
        #expect(OAuthHelpers.constantTimeEqual("abc123", "abc123"))
    }

    @Test func constantTimeEqualReturnsFalseForDifferentStrings() {
        #expect(!OAuthHelpers.constantTimeEqual("abc123", "abc124"))
    }

    @Test func constantTimeEqualReturnsFalseForDifferentLengths() {
        #expect(!OAuthHelpers.constantTimeEqual("short", "longer"))
    }

    @Test func constantTimeEqualHandlesEmptyStrings() {
        #expect(OAuthHelpers.constantTimeEqual("", ""))
    }

    @Test func constantTimeEqualReturnsFalseForEmptyVsNonEmpty() {
        #expect(!OAuthHelpers.constantTimeEqual("", "a"))
    }

    // MARK: oauthConfig

    @Test func oauthConfigForGoogleUsesCorrectEndpoints() {
        let config = AppConfig(oauthGoogleClientId: "google-id")
        let oauth = OAuthHelpers.oauthConfig(
            for: .google,
            appConfig: config,
            clientSecret: "google-secret",
            redirectURI: "http://127.0.0.1:12345/oauth/callback"
        )

        #expect(oauth.clientId == "google-id")
        #expect(oauth.clientSecret == "google-secret")
        #expect(oauth.authorizationEndpoint.host == "accounts.google.com")
        #expect(oauth.tokenEndpoint.host == "oauth2.googleapis.com")
        #expect(oauth.redirectURI == "http://127.0.0.1:12345/oauth/callback")
        #expect(oauth.scopes.contains("openid"))
        #expect(oauth.scopes.contains("email"))
        #expect(oauth.scopes.contains("https://mail.google.com/"))
        #expect(oauth.scopes.contains("https://www.googleapis.com/auth/carddav"))
    }

    @Test func oauthConfigForMicrosoftUsesCorrectEndpoints() {
        let config = AppConfig(oauthMicrosoftClientId: "ms-id")
        let oauth = OAuthHelpers.oauthConfig(
            for: .microsoft,
            appConfig: config,
            clientSecret: "ms-secret",
            redirectURI: "http://127.0.0.1:54321/oauth/callback"
        )

        #expect(oauth.clientId == "ms-id")
        #expect(oauth.clientSecret == "ms-secret")
        #expect(oauth.authorizationEndpoint.host == "login.microsoftonline.com")
        #expect(oauth.tokenEndpoint.host == "login.microsoftonline.com")
        #expect(oauth.scopes == [
            "openid",
            "email",
            "offline_access",
            "https://outlook.office.com/IMAP.AccessAsUser.All",
            "https://outlook.office.com/SMTP.Send",
        ])
    }

    @Test func oauthConfigDefaultsToEmptyClientId() {
        let config = AppConfig() // no OAuth fields set
        let oauth = OAuthHelpers.oauthConfig(for: .google, appConfig: config, clientSecret: nil, redirectURI: "http://127.0.0.1:0/cb")
        #expect(oauth.clientId == "")
    }

    // MARK: oauthClientId

    @Test func oauthClientIdReturnsConfiguredId() {
        let config = AppConfig(oauthGoogleClientId: "my-google-id")
        #expect(OAuthHelpers.oauthClientId(for: .google, appConfig: config) == "my-google-id")
    }

    @Test func oauthClientIdReturnsEmptyWhenNotConfigured() {
        let config = AppConfig()
        #expect(OAuthHelpers.oauthClientId(for: .google, appConfig: config) == "")
        #expect(OAuthHelpers.oauthClientId(for: .microsoft, appConfig: config) == "")
    }

    @Test func oauthClientIdValidationGuardBlocksEmptyId() {
        let config = AppConfig()
        let clientId = OAuthHelpers.oauthClientId(for: .google, appConfig: config)
        #expect(clientId.isEmpty, "Empty client ID should block OAuth flow")
    }

    @Test func oauthClientIdValidationGuardAllowsConfiguredId() {
        let config = AppConfig(oauthMicrosoftClientId: "configured-id")
        let clientId = OAuthHelpers.oauthClientId(for: .microsoft, appConfig: config)
        #expect(!clientId.isEmpty, "Configured client ID should allow OAuth flow")
    }
}

// MARK: - CLIParamBuilders Tests

@Suite
struct CLIParamBuildersTests {

    @Test func buildSendParamsBasic() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Gmail",
            to: ["alice@example.com"],
            subject: "Hello",
            body: "Hi there"
        )

        #expect(params["account"] == .string("Gmail"))
        #expect(params["subject"] == .string("Hello"))
        #expect(params["body"] == .string("Hi there"))

        // to should be array of dictionaries with "email" key
        if case .array(let recipients) = params["to"] {
            #expect(recipients.count == 1)
            if case .dictionary(let dict) = recipients[0] {
                #expect(dict["email"] == .string("alice@example.com"))
            } else {
                Issue.record("Expected dictionary in to array")
            }
        } else {
            Issue.record("Expected array for 'to' param")
        }
    }

    @Test func buildSendParamsWithAttachments() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Gmail",
            to: ["bob@example.com"],
            subject: "Files",
            body: "See attached",
            attachments: ["/tmp/foo.pdf", "/tmp/bar.png"]
        )

        if case .array(let attachments) = params["attachments"] {
            #expect(attachments.count == 2)
            #expect(attachments[0] == .string("/tmp/foo.pdf"))
            #expect(attachments[1] == .string("/tmp/bar.png"))
        } else {
            Issue.record("Expected array for 'attachments' param")
        }
    }

    @Test func buildSendParamsOmitsEmptyAttachments() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Gmail",
            to: ["bob@example.com"],
            subject: "No files",
            body: "Nothing attached"
        )
        #expect(params["attachments"] == nil)
    }

    @Test func buildSendParamsWithCC() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Work",
            to: ["alice@example.com"],
            subject: "CC test",
            body: "body",
            cc: ["charlie@example.com"]
        )

        if case .array(let ccList) = params["cc"] {
            #expect(ccList.count == 1)
            if case .dictionary(let dict) = ccList[0] {
                #expect(dict["email"] == .string("charlie@example.com"))
            }
        } else {
            Issue.record("Expected array for 'cc' param")
        }
    }

    @Test func buildSendParamsOmitsEmptyCCAndBCC() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Work",
            to: ["bob@example.com"],
            subject: "Simple",
            body: "body"
        )
        #expect(params["cc"] == nil)
        #expect(params["bcc"] == nil)
    }

    @Test func buildSendParamsWithHTMLBody() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Gmail",
            to: ["alice@example.com"],
            subject: "HTML",
            body: "plain",
            bodyHtml: "<p>rich</p>"
        )
        #expect(params["bodyHtml"] == .string("<p>rich</p>"))
    }

    @Test func buildSendParamsOmitsNilHTMLBody() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Gmail",
            to: ["alice@example.com"],
            subject: "Plain",
            body: "plain only"
        )
        #expect(params["bodyHtml"] == nil)
    }

    @Test func buildSendParamsMultipleRecipients() {
        let params = CLIParamBuilders.buildSendParams(
            account: "Gmail",
            to: ["a@x.com", "b@x.com", "c@x.com"],
            subject: "Group",
            body: "hi all"
        )

        if case .array(let recipients) = params["to"] {
            #expect(recipients.count == 3)
        } else {
            Issue.record("Expected array for 'to' param")
        }
    }
}

// MARK: - NotificationForwarder Tests

@Suite
struct NotificationForwarderTests {

    @Test func forwardToMCPPrefixesMethod() {
        let ipcNotification = JSONRPCNotification(method: "newMail", params: ["account": .string("Gmail")])
        let mcpNotification = NotificationForwarder.forwardToMCP(ipcNotification)

        #expect(mcpNotification.method == "clawmail/newMail")
        #expect(mcpNotification.params?["account"] == .string("Gmail"))
    }

    @Test func forwardToMCPPreservesParams() {
        let params: [String: AnyCodableValue] = [
            "account": .string("Work"),
            "folder": .string("INBOX"),
            "count": .int(5),
        ]
        let ipcNotification = JSONRPCNotification(method: "connectionStatus", params: params)
        let mcpNotification = NotificationForwarder.forwardToMCP(ipcNotification)

        #expect(mcpNotification.method == "clawmail/connectionStatus")
        #expect(mcpNotification.params?["account"] == .string("Work"))
        #expect(mcpNotification.params?["folder"] == .string("INBOX"))
        #expect(mcpNotification.params?["count"] == .int(5))
    }

    @Test func forwardToMCPHandlesNilParams() {
        let ipcNotification = JSONRPCNotification(method: "error")
        let mcpNotification = NotificationForwarder.forwardToMCP(ipcNotification)

        #expect(mcpNotification.method == "clawmail/error")
        #expect(mcpNotification.params == nil)
    }

    @Test func mcpPrefixConstant() {
        #expect(NotificationForwarder.mcpPrefix == "clawmail/")
    }
}
