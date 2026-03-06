import Testing
import Foundation
import GRDB
@testable import ClawMailCore

/// Regression tests for v1 bug fixes and feature gaps.
/// Each test references the checklist item it covers.
@Suite
struct RegressionTests {

    private static func inMemoryDB() throws -> DatabaseManager {
        try DatabaseManager(inMemory: true)
    }

    // MARK: - Bug #1: MetadataIndex safe flags/uid handling

    @Test func metadataIndexHandlesEmptyFlagsJSON() throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)

        // Insert a message with empty flags — the fix ensures "[]" default works safely
        let summary = EmailSummary(
            id: "empty-flags-msg",
            account: "test",
            folder: "INBOX",
            from: EmailAddress(name: "Sender", email: "sender@test.com"),
            to: [],
            subject: "Test",
            date: Date(),
            flags: []
        )
        try index.upsertMessage(summary)

        let result = try index.getMessage(id: "empty-flags-msg", account: "test")
        #expect(result != nil)
        #expect(result!.flags.isEmpty)
    }

    @Test func metadataIndexRoundTripsFlags() throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)

        let summary = EmailSummary(
            id: "flagged-msg",
            account: "test",
            folder: "INBOX",
            from: EmailAddress(name: "Sender", email: "sender@test.com"),
            to: [],
            subject: "Flagged",
            date: Date(),
            flags: [.seen, .flagged, .answered]
        )
        try index.upsertMessage(summary)

        let result = try index.getMessage(id: "flagged-msg", account: "test")
        #expect(result != nil)
        #expect(result!.flags == [.seen, .flagged, .answered])
    }

    @Test func metadataIndexHandlesNullUID() throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)

        let summary = EmailSummary(
            id: "null-uid-msg",
            account: "test",
            folder: "INBOX",
            from: EmailAddress(name: "Sender", email: "s@test.com"),
            to: [],
            subject: "Test",
            date: Date(),
            uid: nil
        )
        try index.upsertMessage(summary)

        let result = try index.getMessage(id: "null-uid-msg", account: "test")
        #expect(result != nil)
        #expect(result!.uid == nil)
    }

    // MARK: - Bug #9: FTS orphaning on flag-only upserts

    @Test func upsertDoesNotOrphanFTSEntries() throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)

        let summary = EmailSummary(
            id: "fts-orphan-test",
            account: "test",
            folder: "INBOX",
            from: EmailAddress(name: "Sender", email: "sender@test.com"),
            to: [],
            subject: "Searchable Subject",
            date: Date()
        )

        // First insert with body text — creates FTS entry
        try index.upsertMessage(summary, bodyText: "unique searchable body content")

        // Verify search works
        let results1 = try index.search(account: "test", query: "unique searchable body")
        #expect(!results1.isEmpty)

        // Re-upsert with different body — should replace FTS, not orphan
        try index.upsertMessage(summary, bodyText: "completely different replacement text")

        // Old text should NOT match
        let oldResults = try index.search(account: "test", query: "unique searchable body")
        #expect(oldResults.isEmpty)

        // New text should match
        let newResults = try index.search(account: "test", query: "completely different replacement")
        #expect(!newResults.isEmpty)
    }

    @Test func upsertWithoutBodyPreservesNoFTS() throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)

        let summary = EmailSummary(
            id: "no-body-test",
            account: "test",
            folder: "INBOX",
            from: EmailAddress(name: "Sender", email: "sender@test.com"),
            to: [],
            subject: "Flag Update",
            date: Date()
        )

        // Insert with body
        try index.upsertMessage(summary, bodyText: "original body text here")
        let results1 = try index.search(account: "test", query: "original body text")
        #expect(!results1.isEmpty)

        // Re-upsert without body (flag-only update) — old FTS should be cleaned up
        var updated = summary
        updated.flags = [.seen]
        try index.upsertMessage(updated, bodyText: nil)

        // Old FTS entry should be gone (cleaned up before INSERT OR REPLACE)
        let results2 = try index.search(account: "test", query: "original body text")
        #expect(results2.isEmpty)
    }

    // MARK: - Bug #12: MetadataIndex error propagation

    @Test func getMessagePropagatesDecodeErrors() throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)

        // Insert a row with malformed flags_json
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO message_metadata
                    (id, account_label, folder, sender_name, sender_email, recipients_json,
                     subject, date, flags_json, size, has_attachments, uid)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "bad-json-msg", "test", "INBOX", "Sender", "sender@test.com", "[]",
                    "Subject", Date(), "NOT VALID JSON", 100, false, nil as Int64?,
                ]
            )
        }

        // Should throw, not silently return nil (was bug #12)
        #expect(throws: (any Error).self) {
            _ = try index.getMessage(id: "bad-json-msg", account: "test")
        }
    }

    @Test func listMessagesPropagatesDecodeErrors() throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)

        // Insert a valid message
        let good = EmailSummary(
            id: "good-msg", account: "test", folder: "INBOX",
            from: EmailAddress(name: "S", email: "s@t.com"), to: [],
            subject: "Good", date: Date()
        )
        try index.upsertMessage(good)

        // Insert a bad row
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO message_metadata
                    (id, account_label, folder, sender_name, sender_email, recipients_json,
                     subject, date, flags_json, size, has_attachments, uid)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    "bad-msg", "test", "INBOX", "S", "s@t.com", "[]",
                    "Bad", Date(), "{invalid}", 50, false, nil as Int64?,
                ]
            )
        }

        // listMessages should throw, not silently skip the bad row
        #expect(throws: (any Error).self) {
            _ = try index.listMessages(account: "test", folder: "INBOX")
        }
    }

    // MARK: - Feature #21: has:attachment search query parsing

    @Test func searchEnginesParsesHasAttachment() {
        let engine = SearchEngine()
        let query = engine.parseQuery("from:alice@test.com has:attachment")

        #expect(query.from == "alice@test.com")
        #expect(query.hasAttachment == true)
    }

    @Test func searchEngineHasAttachmentCaseInsensitive() {
        let engine = SearchEngine()
        let query = engine.parseQuery("has:Attachment")
        #expect(query.hasAttachment == true)
    }

    @Test func searchEngineHasAttachmentNotInFTS() {
        // has:attachment should NOT appear in ftsQuery — it's handled at IMAP layer
        let engine = SearchEngine()
        let query = engine.parseQuery("has:attachment subject:report")
        #expect(query.hasAttachment == true)
        #expect(query.ftsQuery != nil)
        #expect(query.ftsQuery!.contains("subject:"))
        // ftsQuery should not mention "attachment"
        #expect(!query.ftsQuery!.lowercased().contains("attachment"))
    }

    // MARK: - Feature #21: IMAP hasAttachment criteria

    @Test func imapHasAttachmentCriteria() {
        let criteria = IMAPSearchCriteria.hasAttachment
        let cmd = criteria.commandString()
        #expect(cmd == "HEADER Content-Type \"multipart/mixed\"")
    }

    @Test func imapHasAttachmentCombinesWithOtherCriteria() {
        let combined = IMAPSearchCriteria.and(.from("alice@test.com"), .hasAttachment)
        let cmd = combined.commandString()
        #expect(cmd.contains("FROM"))
        #expect(cmd.contains("HEADER Content-Type"))
    }

    // MARK: - Feature #23: AuditLog offset parameter

    @Test func auditLogOffsetPagination() throws {
        let db = try Self.inMemoryDB()
        let auditLog = AuditLog(db: db)

        // Insert 5 entries
        for i in 0..<5 {
            try auditLog.log(entry: AuditEntry(
                timestamp: Date().addingTimeInterval(Double(i)),
                interface: .cli,
                operation: "test.op\(i)",
                account: "test",
                result: .success
            ))
        }

        // Fetch all
        let all = try auditLog.list(limit: 10, offset: 0)
        #expect(all.count == 5)

        // Fetch with offset 2
        let page2 = try auditLog.list(limit: 10, offset: 2)
        #expect(page2.count == 3)

        // Fetch with offset 4
        let page4 = try auditLog.list(limit: 10, offset: 4)
        #expect(page4.count == 1)

        // Fetch with offset beyond count
        let empty = try auditLog.list(limit: 10, offset: 10)
        #expect(empty.isEmpty)
    }

    @Test func auditLogOffsetWithLimit() throws {
        let db = try Self.inMemoryDB()
        let auditLog = AuditLog(db: db)

        for i in 0..<10 {
            try auditLog.log(entry: AuditEntry(
                timestamp: Date().addingTimeInterval(Double(i)),
                interface: .rest,
                operation: "test.op",
                account: "test",
                result: .success
            ))
        }

        // Page through with limit 3
        let page0 = try auditLog.list(limit: 3, offset: 0)
        let page1 = try auditLog.list(limit: 3, offset: 3)
        let page2 = try auditLog.list(limit: 3, offset: 6)
        let page3 = try auditLog.list(limit: 3, offset: 9)

        #expect(page0.count == 3)
        #expect(page1.count == 3)
        #expect(page2.count == 3)
        #expect(page3.count == 1)
    }

    // MARK: - Feature #25: GuardrailEngine first-time recipient approval

    @Test func guardrailBlocksUnapprovedRecipients() async throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        let config = GuardrailConfig(firstTimeRecipientApproval: true)
        let engine = GuardrailEngine(
            config: { config },
            auditLog: auditLog,
            metadataIndex: index
        )

        let recipients = [
            EmailAddress(name: "New", email: "new@example.com"),
            EmailAddress(name: "Also New", email: "also-new@example.com"),
        ]

        let result = try await engine.checkSend(account: "test", recipients: recipients)
        if case .pendingApproval(let emails) = result {
            #expect(emails.count == 2)
            #expect(emails.contains("new@example.com"))
            #expect(emails.contains("also-new@example.com"))
        } else {
            Issue.record("Expected pendingApproval, got \(result)")
        }
    }

    @Test func guardrailAllowsApprovedRecipients() async throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        // Pre-approve recipient
        try index.approveRecipient(email: "known@example.com", account: "test")

        let config = GuardrailConfig(firstTimeRecipientApproval: true)
        let engine = GuardrailEngine(
            config: { config },
            auditLog: auditLog,
            metadataIndex: index
        )

        let recipients = [EmailAddress(name: "Known", email: "known@example.com")]
        let result = try await engine.checkSend(account: "test", recipients: recipients)

        if case .allowed = result {
            // Expected
        } else {
            Issue.record("Expected allowed for approved recipient, got \(result)")
        }
    }

    @Test func guardrailApprovalIsScopedPerAccount() async throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        try index.approveRecipient(email: "known@example.com", account: "personal")

        let config = GuardrailConfig(firstTimeRecipientApproval: true)
        let engine = GuardrailEngine(
            config: { config },
            auditLog: auditLog,
            metadataIndex: index
        )

        let recipients = [EmailAddress(name: "Known", email: "known@example.com")]

        let personalResult = try await engine.checkSend(account: "personal", recipients: recipients)
        if case .allowed = personalResult {
            // Expected
        } else {
            Issue.record("Expected approval on personal account, got \(personalResult)")
        }

        let workResult = try await engine.checkSend(account: "work", recipients: recipients)
        if case .pendingApproval(let emails) = workResult {
            #expect(emails == ["known@example.com"])
        } else {
            Issue.record("Expected work account to require approval, got \(workResult)")
        }
    }

    @Test func guardrailSkipsApprovalWhenDisabled() async throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        let config = GuardrailConfig(firstTimeRecipientApproval: false)
        let engine = GuardrailEngine(
            config: { config },
            auditLog: auditLog,
            metadataIndex: index
        )

        let recipients = [EmailAddress(name: "Anyone", email: "anyone@example.com")]
        let result = try await engine.checkSend(account: "test", recipients: recipients)

        if case .allowed = result {
            // Expected — approval check disabled
        } else {
            Issue.record("Expected allowed when approval disabled, got \(result)")
        }
    }

    @Test func guardrailMixedApprovedAndUnapproved() async throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        try index.approveRecipient(email: "known@example.com", account: "test")

        let config = GuardrailConfig(firstTimeRecipientApproval: true)
        let engine = GuardrailEngine(
            config: { config },
            auditLog: auditLog,
            metadataIndex: index
        )

        let recipients = [
            EmailAddress(name: "Known", email: "known@example.com"),
            EmailAddress(name: "Unknown", email: "unknown@example.com"),
        ]
        let result = try await engine.checkSend(account: "test", recipients: recipients)

        if case .pendingApproval(let emails) = result {
            #expect(emails == ["unknown@example.com"])
        } else {
            Issue.record("Expected pendingApproval for unknown recipient, got \(result)")
        }
    }

    // MARK: - Feature #26: Domain blocklist guardrail

    @Test func guardrailBlocksBlocklistedDomain() async throws {
        let db = try Self.inMemoryDB()
        let index = MetadataIndex(db: db)
        let auditLog = AuditLog(db: db)

        let config = GuardrailConfig(domainBlocklist: ["blocked.com"])
        let engine = GuardrailEngine(
            config: { config },
            auditLog: auditLog,
            metadataIndex: index
        )

        let recipients = [EmailAddress(name: "Bad", email: "user@blocked.com")]
        let result = try await engine.checkSend(account: "test", recipients: recipients)

        if case .blocked(let error) = result {
            if case .domainBlocked = error {
                // Expected
            } else {
                Issue.record("Expected domainBlocked error, got \(error)")
            }
        } else {
            Issue.record("Expected blocked result, got \(result)")
        }
    }

    // MARK: - Search query combined parsing

    @Test func searchQueryCombinedFilters() {
        let engine = SearchEngine()
        let query = engine.parseQuery("from:alice subject:report has:attachment is:unread")

        #expect(query.from == "alice")
        #expect(query.subject == "report")
        #expect(query.hasAttachment == true)
        #expect(query.isUnread == true)
        #expect(query.freeText == nil)
    }

    @Test func searchQueryFreeTextFallback() {
        let engine = SearchEngine()
        let query = engine.parseQuery("hello world")

        #expect(query.freeText == "hello world")
        #expect(query.from == nil)
        #expect(query.hasAttachment == nil)
    }
}
