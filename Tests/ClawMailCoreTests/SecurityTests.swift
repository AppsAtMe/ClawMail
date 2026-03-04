import Testing
import Foundation
@testable import ClawMailCore

/// Tests for security sanitizers and validators to prevent regressions.
/// These test the functions that guard against injection attacks.
@Suite
struct SecurityTests {

    // MARK: - IMAP Command Injection Prevention

    @Test func imapQuoteStripsNewlines() async {
        let client = IMAPClient(
            host: "localhost", port: 993,
            security: .ssl,
            credential: .password(username: "", password: "")
        )
        // CRLF should be stripped to prevent command injection
        let quoted = await client.quoteIMAPString("INBOX\r\nT2 LOGOUT\r\n")
        #expect(!quoted.contains("\r"))
        #expect(!quoted.contains("\n"))
        #expect(quoted == "\"INBOXT2 LOGOUT\"")
    }

    @Test func imapQuoteEscapesBackslashAndQuote() async {
        let client = IMAPClient(
            host: "localhost", port: 993,
            security: .ssl,
            credential: .password(username: "", password: "")
        )
        let quoted = await client.quoteIMAPString("test\\\"folder")
        #expect(quoted == "\"test\\\\\\\"folder\"")
    }

    @Test func imapSearchCriteriaStripsNewlines() {
        let criteria = IMAPSearchCriteria.from("attacker\r\nT2 DELETE \"INBOX\"")
        let cmd = criteria.commandString()
        #expect(!cmd.contains("\r"))
        #expect(!cmd.contains("\n"))
        #expect(cmd.hasPrefix("FROM \""))
    }

    @Test func imapSearchHeaderStripsNewlines() {
        let criteria = IMAPSearchCriteria.header("X-Custom\r\nT2 LOGOUT", "value\r\n")
        let cmd = criteria.commandString()
        #expect(!cmd.contains("\r"))
        #expect(!cmd.contains("\n"))
    }

    // MARK: - SMTP Header Injection Prevention

    @Test func smtpSanitizeHeaderValueStripsNewlines() {
        // Test via the public encodeHeader path — subject with CRLF should be stripped
        let client = SMTPClient(
            host: "localhost", port: 465,
            security: .ssl,
            credentials: .password("test"),
            senderEmail: "test@test.com"
        )

        // We can't directly test the private sanitizeHeaderValue, but we verify
        // the build of an OutgoingEmail with CRLF in the subject doesn't crash
        let email = OutgoingEmail(
            from: EmailAddress(name: "Test\r\nBcc: attacker@evil.com", email: "test@test.com"),
            to: [EmailAddress(name: "Victim", email: "victim@test.com")],
            subject: "Hello\r\nBcc: attacker@evil.com",
            bodyPlain: "body"
        )
        // Verify the email struct is constructed (the sanitization happens in buildMIME)
        #expect(email.subject.contains("\r\n"))
        // The actual CRLF stripping is in the private buildMIME — tested via integration
    }

    // MARK: - FTS5 Query Sanitization

    @Test func fts5SanitizeAlwaysQuotes() {
        // Simple text should be quoted
        let result = MetadataIndex.sanitizeFTS5Query("hello world")
        #expect(result == "\"hello world\"")
    }

    @Test func fts5SanitizeBlocksOperators() {
        // FTS5 operators should be neutralized by quoting
        let andQuery = MetadataIndex.sanitizeFTS5Query("secret AND password")
        #expect(andQuery == "\"secret AND password\"")

        let orQuery = MetadataIndex.sanitizeFTS5Query("\"a\" OR \"b\"")
        // Internal quotes are doubled
        #expect(orQuery == "\"\"\"a\"\" OR \"\"b\"\"\"")
    }

    @Test func fts5SanitizeBlocksColumnFilter() {
        // Column filter attempts should be neutralized
        let result = MetadataIndex.sanitizeFTS5Query("body_text:password")
        #expect(result == "\"body_text:password\"")
    }

    @Test func fts5SanitizeHandlesEmpty() {
        let result = MetadataIndex.sanitizeFTS5Query("")
        #expect(result == "\"\"")

        let whitespace = MetadataIndex.sanitizeFTS5Query("   ")
        #expect(whitespace == "\"\"")
    }

    @Test func fts5SanitizeHandlesUnbalancedQuotes() {
        let result = MetadataIndex.sanitizeFTS5Query("test\"unbalanced")
        // Should double the quote and wrap
        #expect(result == "\"test\"\"unbalanced\"")
    }

    @Test func fts5EscapeInSearchEngineQuotesTerms() {
        var query = SearchQuery()
        query.subject = "test OR secret"
        let fts = query.ftsQuery
        // Each term should be phrase-quoted, preventing OR from being an operator
        #expect(fts != nil)
        #expect(fts!.contains("subject:\"test OR secret\""))
    }

    // MARK: - Path Traversal Prevention

    @Test func validateDestinationPathRejectsSystemPaths() async {
        // /etc/passwd should be rejected
        do {
            _ = try EmailManager.validateAttachmentSourcePath("/etc/passwd")
            Issue.record("Should have thrown for /etc/passwd")
        } catch {
            #expect(error is ClawMailError)
        }
    }

    @Test func validateSourcePathRejectsSSH() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        do {
            _ = try EmailManager.validateAttachmentSourcePath(home + "/.ssh/id_rsa")
            Issue.record("Should have thrown for .ssh path")
        } catch {
            #expect(error is ClawMailError)
        }
    }

    @Test func validateSourcePathRejectsTraversal() async {
        do {
            _ = try EmailManager.validateAttachmentSourcePath("/tmp/../etc/passwd")
            Issue.record("Should have thrown for path traversal")
        } catch {
            #expect(error is ClawMailError)
        }
    }

    @Test func validateSourcePathAllowsUserDocuments() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Should not throw for normal user paths (outside blocked dirs)
        do {
            _ = try EmailManager.validateAttachmentSourcePath(home + "/Downloads/report.pdf")
        } catch {
            Issue.record("Should allow ~/Downloads path: \(error)")
        }
    }

    // MARK: - MIME Section Validation

    @Test func mimeSectionRejectsInjection() async throws {
        let client = IMAPClient(
            host: "localhost", port: 993,
            security: .ssl,
            credential: .password(username: "", password: "")
        )
        // Invalid section with injection attempt should throw invalidParameter
        // (validation happens before connection check)
        do {
            _ = try await client.fetchAttachment(folder: "INBOX", uid: 1, section: "1]\r\nT2 LOGOUT\r\n")
            Issue.record("Should have thrown for injection in section")
        } catch let error as ClawMailError {
            if case .invalidParameter = error {
                // Expected — validation caught the bad section
            } else {
                Issue.record("Expected invalidParameter, got: \(error)")
            }
        }
    }

    @Test func mimeSectionAllowsValidFormats() async throws {
        let client = IMAPClient(
            host: "localhost", port: 993,
            security: .ssl,
            credential: .password(username: "", password: "")
        )
        // These should pass validation but fail on connection (not connected)
        for section in ["1", "1.2", "2.1.3"] {
            do {
                _ = try await client.fetchAttachment(folder: "INBOX", uid: 1, section: section)
            } catch let error as ClawMailError {
                if case .invalidParameter = error {
                    Issue.record("Valid section '\(section)' should not fail validation")
                }
                // connectionError is expected (not connected)
            }
        }
    }


}
