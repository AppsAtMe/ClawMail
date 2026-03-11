# ClawMail — Implementation Blueprint

This blueprint provides the step-by-step build sequence for ClawMail. Each phase is self-contained with clear inputs, outputs, and verification criteria. Phases are ordered by dependency — each phase builds on the previous ones.

**Reference**: See `SPECIFICATION.md` for full feature descriptions, data models, and API contracts.

**Key Principle**: Build from the inside out. Core models and protocols first, then the engine that orchestrates them, then the interface layers (CLI, MCP, REST), and finally the macOS UI shell that wraps everything.

---

## Phase 0 — Project Scaffolding

**Goal**: Establish the Swift Package Manager project structure with all targets, dependencies, and build configuration.

### Steps

1. **Create `Package.swift`** with four targets:
   - `ClawMailCore` — library target (shared business logic)
   - `ClawMailApp` — executable target (macOS menu bar app)
   - `ClawMailCLI` — executable target (CLI tool)
   - `ClawMailMCP` — executable target (MCP stdio server)

2. **Declare dependencies** in `Package.swift`:
   ```
   swift-nio                  — networking foundation
   swift-nio-ssl              — TLS for IMAP/SMTP
   swift-argument-parser      — CLI parsing
   GRDB.swift                 — SQLite (preferred over SQLite.swift for its active record pattern and FTS5 support)
   hummingbird                — lightweight HTTP server for REST API
   SwiftSoup                  — HTML parsing for email cleaning
   KeychainAccess             — macOS Keychain wrapper
   ```
   For IMAP: evaluate `swift-nio-imap` (Apple's package). If insufficient, plan to implement IMAP client directly on SwiftNIO.
   For SMTP: evaluate available packages. `SwiftSMTP` by IBM is archived; plan to implement on SwiftNIO.
   For MCP: no mature Swift SDK exists as of this writing. Implement MCP stdio protocol directly (JSON-RPC 2.0 over stdin/stdout — straightforward).

3. **Create directory structure** matching the spec's project layout. Create placeholder `// TODO` files for each source file so the project compiles as an empty shell.

4. **Set minimum deployment target** to macOS 14.0 (Sonoma).

5. **Enable strict concurrency checking** in Package.swift: `swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]`

6. **Create `Sources/ClawMailApp/Resources/Info.plist`** with:
   - `LSUIElement = true` (no Dock icon)
   - Bundle identifier: `com.clawmail.app`

### Verification
- `swift build` compiles successfully with no errors
- All four targets exist and produce executables/library
- Directory structure matches the spec

---

## Phase 1 — Core Data Models

**Goal**: Define all shared data types used across the application.

### Files to Create

**`Sources/ClawMailCore/Models/Account.swift`**
- `Account` struct (see spec for fields): id, label, emailAddress, displayName, auth method, IMAP/SMTP/CalDAV/CardDAV config, enabled flag, connection status
- `AuthMethod` enum: `.password`, `.oauth2(provider: OAuthProvider)`
- `OAuthProvider` enum: `.google`, `.microsoft`
- `ConnectionSecurity` enum: `.ssl`, `.starttls`
- `ConnectionStatus` enum: `.disconnected`, `.connecting`, `.connected`, `.error(String)`
- All types conform to `Codable`, `Sendable`, and `Identifiable` where appropriate

**`Sources/ClawMailCore/Models/Email.swift`**
- `EmailAddress` struct: name (optional), email
- `EmailSummary` struct: id, account, folder, from, to, cc, subject, date, flags, size, hasAttachments
- `EmailMessage` struct: full message with bodyPlain, bodyPlainRaw, bodyHtml, attachments array, headers dict
- `EmailAttachment` struct: filename, mimeType, size
- `EmailFlag` enum: seen, flagged, answered, draft
- `SendEmailRequest` struct: account, to, cc, bcc, subject, body, bodyHtml, attachments (file paths), inReplyTo
- `ReplyEmailRequest` struct: account, originalMessageId, body, bodyHtml, attachments, replyAll

**`Sources/ClawMailCore/Models/CalendarEvent.swift`**
- `CalendarInfo` struct: name, color, isDefault
- `CalendarEvent` struct: id, calendar, title, start, end, location, description, attendees, recurrence, reminders, allDay
- `EventAttendee` struct: name, email, status
- `EventReminder` struct: minutesBefore
- `CreateEventRequest`, `UpdateEventRequest` structs

**`Sources/ClawMailCore/Models/Contact.swift`**
- `AddressBook` struct: name
- `Contact` struct: id, addressBook, displayName, firstName, lastName, emails, phones, organization, title, notes
- `ContactEmail` struct: type, address
- `ContactPhone` struct: type, number
- `CreateContactRequest`, `UpdateContactRequest` structs

**`Sources/ClawMailCore/Models/Task.swift`**
- `TaskList` struct: name
- `TaskItem` struct: id, taskList, title, description, due, priority, status, percentComplete, created, modified
- `TaskPriority` enum: low, medium, high
- `TaskStatus` enum: needsAction, inProcess, completed, cancelled
- `CreateTaskRequest`, `UpdateTaskRequest` structs

**`Sources/ClawMailCore/Models/AuditEntry.swift`**
- `AuditEntry` struct: id, timestamp, interface (mcp/cli/rest), operation, account, parameters (JSON), result (success/failure), details (JSON)
- `AgentInterface` enum: mcp, cli, rest

**`Sources/ClawMailCore/Models/Errors.swift`**
- `ClawMailError` enum conforming to `Error` and `Codable`:
  - Cases matching all error codes from the spec: accountNotFound, accountDisconnected, authFailed, messageNotFound, folderNotFound, rateLimitExceeded(retryAfter:), domainBlocked, recipientPendingApproval, agentAlreadyConnected, connectionError(String), invalidParameter(String), serverError(String), calendarNotAvailable, contactsNotAvailable
- `ErrorResponse` struct matching the spec's JSON error format, with `toJSON()` method

**`Sources/ClawMailCore/Models/Config.swift`**
- `AppConfig` struct matching the spec's `config.json` schema
- `GuardrailConfig` struct: sendRateLimit, domainAllowlist, domainBlocklist, firstTimeRecipientApproval
- `RateLimitConfig` struct: maxPerMinute, maxPerHour, maxPerDay
- Load/save methods targeting `~/Library/Application Support/ClawMail/config.json`

### Verification
- All models compile
- JSON round-trip encoding/decoding works for all `Codable` types (write unit tests)
- Models are `Sendable` (passes strict concurrency checks)

---

## Phase 2 — Credential Storage (Keychain)

**Goal**: Secure credential management using macOS Keychain.

### Files to Create

**`Sources/ClawMailCore/Auth/KeychainManager.swift`**
- Actor `KeychainManager` (actor for thread safety)
- Service name constant: `"com.clawmail"`
- Methods:
  - `savePassword(accountId: UUID, password: String)` — store IMAP/SMTP password
  - `getPassword(accountId: UUID) -> String?`
  - `deletePassword(accountId: UUID)`
  - `saveOAuthTokens(accountId: UUID, accessToken: String, refreshToken: String, expiresAt: Date)`
  - `getOAuthTokens(accountId: UUID) -> OAuthTokens?`
  - `deleteOAuthTokens(accountId: UUID)`
  - `saveAPIKey(_ key: String)` — store REST API key
  - `getAPIKey() -> String?`
  - `generateAPIKey() -> String` — generate cryptographically random 32-byte hex string, save and return
  - `deleteAll(accountId: UUID)` — cleanup on account removal

**`Sources/ClawMailCore/Auth/CredentialStore.swift`**
- Actor `CredentialStore` that wraps `KeychainManager` and `AppConfig`
- Provides higher-level methods:
  - `credentialsFor(account: Account) -> Credentials` — returns the right credential type based on account auth method
  - `Credentials` enum: `.password(String)`, `.oauth2(accessToken: String, refreshToken: String, expiresAt: Date)`

### Verification
- Unit tests: save, retrieve, delete passwords and tokens
- Unit tests: API key generation produces valid hex strings of correct length
- Verify Keychain items appear in Keychain Access.app during development

---

## Phase 3 — SQLite Database Layer

**Goal**: Set up the local SQLite database for metadata indexing, full-text search, and audit logging.

### Files to Create

**`Sources/ClawMailCore/Storage/DatabaseManager.swift`**
- Class `DatabaseManager` wrapping GRDB's `DatabasePool`
- Database path: `~/Library/Application Support/ClawMail/metadata.sqlite`
- `initialize()` method that:
  - Creates the Application Support directory if needed
  - Opens/creates the database
  - Runs migrations

- **Schema migrations** (using GRDB's migration system):

  Migration 1 — `createMessageMetadata`:
  ```sql
  CREATE TABLE message_metadata (
    id TEXT PRIMARY KEY,           -- IMAP message ID
    account_label TEXT NOT NULL,
    folder TEXT NOT NULL,
    sender_name TEXT,
    sender_email TEXT NOT NULL,
    recipients_json TEXT NOT NULL,  -- JSON array of {name, email, type}
    subject TEXT,
    date DATETIME NOT NULL,
    flags_json TEXT NOT NULL,       -- JSON array of flag strings
    size INTEGER,
    has_attachments BOOLEAN NOT NULL DEFAULT 0,
    uid INTEGER,                   -- IMAP UID for sync
    UNIQUE(account_label, folder, uid)
  );
  CREATE INDEX idx_msg_account_folder ON message_metadata(account_label, folder);
  CREATE INDEX idx_msg_date ON message_metadata(date);
  CREATE INDEX idx_msg_sender ON message_metadata(sender_email);
  ```

  Migration 2 — `createFTSIndex`:
  ```sql
  CREATE VIRTUAL TABLE message_fts USING fts5(
    subject,
    body_text,
    sender_email,
    sender_name,
    content=message_metadata,
    content_rowid=rowid
  );
  ```

  Migration 3 — `createAuditLog`:
  ```sql
  CREATE TABLE audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    interface TEXT NOT NULL,        -- 'mcp', 'cli', 'rest'
    operation TEXT NOT NULL,        -- 'email.send', 'calendar.create', etc.
    account_label TEXT,
    parameters_json TEXT,
    result TEXT NOT NULL,           -- 'success' or 'failure'
    details_json TEXT
  );
  CREATE INDEX idx_audit_timestamp ON audit_log(timestamp);
  CREATE INDEX idx_audit_account ON audit_log(account_label);
  CREATE INDEX idx_audit_operation ON audit_log(operation);
  ```

  Migration 4 — `createSyncState`:
  ```sql
  CREATE TABLE sync_state (
    account_label TEXT NOT NULL,
    folder TEXT NOT NULL,
    uid_validity INTEGER,
    highest_mod_seq INTEGER,
    last_sync DATETIME,
    PRIMARY KEY (account_label, folder)
  );
  ```

  Migration 5 — `createApprovedRecipients`:
  ```sql
  CREATE TABLE approved_recipients (
    email TEXT PRIMARY KEY,
    approved_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    account_label TEXT NOT NULL
  );
  ```

  Migration 6 — `createPendingApprovals`:
  ```sql
  CREATE TABLE pending_approvals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT NOT NULL,
    account_label TEXT NOT NULL,
    send_request_json TEXT NOT NULL,  -- serialized SendEmailRequest
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status TEXT NOT NULL DEFAULT 'pending'  -- 'pending', 'approved', 'rejected'
  );
  ```

**`Sources/ClawMailCore/Storage/MetadataIndex.swift`**
- Class `MetadataIndex` backed by `DatabaseManager`
- Methods:
  - `upsertMessage(_ summary: EmailSummary, bodyText: String?)` — insert/update metadata + FTS
  - `deleteMessage(id: String, account: String)`
  - `getMessage(id: String, account: String) -> EmailSummary?`
  - `listMessages(account: String, folder: String, limit: Int, offset: Int, sort: SortOrder) -> [EmailSummary]`
  - `search(account: String, query: SearchQuery, limit: Int, offset: Int) -> [EmailSummary]` — uses FTS5
  - `getFolders(account: String) -> [FolderInfo]`
  - `getSyncState(account: String, folder: String) -> SyncState?`
  - `updateSyncState(account: String, folder: String, state: SyncState)`
  - `purgeAccount(label: String)` — delete all data for an account

**`Sources/ClawMailCore/Storage/AuditLog.swift`**
- Class `AuditLog` backed by `DatabaseManager`
- Methods:
  - `log(entry: AuditEntry)` — insert new log entry
  - `list(limit: Int, offset: Int, account: String?, operation: String?, from: Date?, to: Date?) -> [AuditEntry]`
  - `purgeOlderThan(days: Int)` — cleanup old entries
  - `count(account: String?, operation: String?) -> Int`

### Verification
- Unit tests: database creation, all migrations run successfully
- Unit tests: CRUD operations on all tables
- Unit tests: FTS5 search returns correct results
- Unit tests: audit log insertion and filtered retrieval
- Test database file appears at expected path

---

## Phase 4 — IMAP Client

**Goal**: Implement a full IMAP client capable of connecting, authenticating (password + XOAUTH2), listing folders, fetching messages, searching, managing flags, moving/deleting messages, and maintaining IDLE connections.

### Design Notes

This is the most substantial protocol implementation in the project. Use SwiftNIO for the network layer. Evaluate Apple's `swift-nio-imap` package — if it provides a usable IMAP parser and command builder, use it. If it's too low-level or incomplete, implement IMAP4rev1 commands directly over a SwiftNIO `Channel`.

The IMAP client should be an actor to serialize access to the connection.

### Files to Create

**`Sources/ClawMailCore/Email/IMAPClient.swift`**
- Actor `IMAPClient`
- Initialization: host, port, security, credentials (password or OAuth2 token)
- Connection management:
  - `connect()` — establish TLS connection, perform IMAP greeting
  - `authenticate()` — LOGIN or XOAUTH2 based on credential type
  - `disconnect()`
  - `isConnected: Bool`
  - Automatic reconnection on connection drop

- Mailbox operations:
  - `listFolders() -> [IMAPFolder]` — LIST command
  - `selectFolder(_ name: String) -> MailboxStatus` — SELECT command, returns exists/recent/unseen/uidValidity/uidNext
  - `createFolder(_ name: String)`
  - `deleteFolder(_ name: String)`

- Message operations:
  - `fetchMessageSummaries(folder: String, range: UIDRange) -> [IMAPMessageSummary]` — FETCH (FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE)
  - `fetchMessageBody(folder: String, uid: UInt32) -> IMAPMessageBody` — FETCH BODY[] or BODY.PEEK[]
  - `fetchMessageHeaders(folder: String, uid: UInt32) -> [String: String]` — FETCH BODY.PEEK[HEADER]
  - `searchMessages(folder: String, criteria: IMAPSearchCriteria) -> [UInt32]` — SEARCH command
  - `moveMessage(uid: UInt32, from: String, to: String)` — MOVE or COPY+DELETE
  - `deleteMessage(uid: UInt32, folder: String, permanent: Bool)` — flag \Deleted + EXPUNGE, or move to Trash
  - `updateFlags(uid: UInt32, folder: String, add: [EmailFlag], remove: [EmailFlag])` — STORE command
  - `fetchAttachment(folder: String, uid: UInt32, section: String) -> Data` — FETCH BODY[section]

- Sync support:
  - `getUIDValidity(folder: String) -> UInt32`
  - `getHighestModSeq(folder: String) -> UInt64?` — CONDSTORE
  - `fetchChangedSince(folder: String, modSeq: UInt64) -> [IMAPMessageSummary]` — QRESYNC

- IMAP types (internal):
  - `IMAPFolder`: name, delimiter, attributes, children
  - `IMAPMessageSummary`: uid, flags, envelope (from/to/cc/subject/date/messageId/inReplyTo), bodyStructure, size
  - `IMAPMessageBody`: raw MIME data
  - `IMAPSearchCriteria`: enum for building SEARCH commands
  - `MailboxStatus`: exists, recent, unseen, uidValidity, uidNext, highestModSeq

- MIME parsing (can use a lightweight MIME parser or implement):
  - Parse `Content-Type`, `Content-Transfer-Encoding`, `Content-Disposition`
  - Decode quoted-printable and base64 body parts
  - Extract plain text and HTML alternatives from multipart messages
  - Extract attachment metadata from bodystructure

**`Sources/ClawMailCore/Email/IMAPIdleMonitor.swift`**
- Actor `IMAPIdleMonitor`
- Maintains a separate IMAP connection dedicated to IDLE
- `start(account: Account, folders: [String], onNewMail: @Sendable (String, String) -> Void)` — begin IDLE on specified folders
- `stop()`
- Behavior:
  - Opens an IMAP connection, authenticates
  - For each folder in the list, issues IDLE command
  - When server sends EXISTS notification, calls the `onNewMail` callback with (accountLabel, folder)
  - Automatically re-issues IDLE every 29 minutes (RFC 2177 recommends < 30 min)
  - Reconnects automatically on connection drop
  - Note: IMAP IDLE only works on one folder per connection. For multiple folders, either use multiple connections or cycle between them.
  - **Recommended approach for MVP**: Single IDLE connection on INBOX only. Document that additional folder monitoring is a future enhancement.

### Verification
- Integration test: connect to a real IMAP server (use a test account)
- Integration test: list folders, select INBOX, fetch summaries
- Integration test: fetch full message body, parse MIME
- Integration test: IDLE connection receives notifications
- Unit test: MIME parsing with sample email data
- Unit test: IMAP command building produces correct protocol strings

---

## Phase 5 — SMTP Client

**Goal**: Send emails via SMTP with support for password and XOAUTH2 authentication, TLS, attachments, and proper MIME construction.

### Files to Create

**`Sources/ClawMailCore/Email/SMTPClient.swift`**
- Actor `SMTPClient`
- Initialization: host, port, security, credentials
- Methods:
  - `connect()` — establish connection, EHLO, STARTTLS if needed
  - `authenticate()` — AUTH PLAIN, AUTH LOGIN, or AUTH XOAUTH2
  - `send(message: OutgoingEmail) -> String` — send and return message ID
  - `disconnect()`

- `OutgoingEmail` struct:
  - from: EmailAddress
  - to: [EmailAddress]
  - cc: [EmailAddress]
  - bcc: [EmailAddress]
  - subject: String
  - bodyPlain: String
  - bodyHtml: String? (optional)
  - attachments: [OutgoingAttachment]
  - inReplyTo: String? (message ID for threading headers)
  - references: String? (References header value)
  - customHeaders: [String: String]

- `OutgoingAttachment` struct:
  - filePath: String
  - filename: String (derived from path if not specified)
  - mimeType: String (detected from file extension)

- MIME construction:
  - Build proper multipart/mixed (when attachments present) or multipart/alternative (when HTML present) MIME messages
  - Set Message-ID header (generate unique ID using domain from sender address)
  - Set Date header
  - Set In-Reply-To and References headers when replying
  - Base64-encode attachments
  - Encode headers with RFC 2047 when non-ASCII characters present
  - Set Content-Transfer-Encoding appropriately

### Verification
- Integration test: send an email to a test account
- Integration test: send with attachment, verify received
- Integration test: send with HTML body
- Unit test: MIME message construction produces valid RFC 2822 output
- Unit test: header encoding handles non-ASCII correctly

---

## Phase 6 — Email Manager & Cleaner

**Goal**: Build the high-level email management layer that coordinates IMAP, SMTP, the metadata index, and email body cleaning.

### Files to Create

**`Sources/ClawMailCore/Email/EmailCleaner.swift`**
- Struct `EmailCleaner`
- `clean(plainText: String) -> String`:
  - Strip email signatures (detect `-- \n` delimiter, common signature patterns)
  - Remove quoted reply blocks (lines starting with `>`)
  - Collapse excessive blank lines (3+ newlines → 2)
  - Trim leading/trailing whitespace
- `extractPlainTextFromHTML(_ html: String) -> String`:
  - Use SwiftSoup to parse HTML
  - Extract text content, preserving paragraph breaks
  - Strip style/script tags entirely
  - Convert `<br>`, `<p>`, `<div>` to newlines
  - Convert `<a href="...">text</a>` to `text (URL)`

**`Sources/ClawMailCore/Email/EmailManager.swift`**
- Actor `EmailManager`
- Dependencies: `IMAPClient`, `SMTPClient`, `MetadataIndex`, `EmailCleaner`, `IMAPIdleMonitor`
- Initialization: takes an `Account` and sets up IMAP/SMTP clients with proper credentials

- Connection lifecycle:
  - `connect()` — connect both IMAP and SMTP, start IDLE monitor
  - `disconnect()` — teardown all connections
  - `connectionStatus: ConnectionStatus` — current state

- High-level operations (these are what the agent interfaces call):
  - `listMessages(folder: String, limit: Int, offset: Int, sort: SortOrder) -> [EmailSummary]`
    - Query local metadata index first
    - If index is stale (based on sync state), refresh from IMAP
  - `readMessage(id: String) -> EmailMessage`
    - Fetch full body from IMAP
    - Parse MIME into structured parts
    - Run `EmailCleaner` on plain text body
    - Return `EmailMessage` with both cleaned and raw text
  - `sendMessage(_ request: SendEmailRequest) -> String`
    - Build `OutgoingEmail` from request
    - Read attachment files from filesystem paths
    - Send via SMTP
    - Return generated message ID
  - `replyToMessage(_ request: ReplyEmailRequest) -> String`
    - Fetch original message headers (In-Reply-To, References)
    - Build reply with proper headers and recipients
    - Send via SMTP
  - `forwardMessage(account: String, messageId: String, to: [EmailAddress], body: String?, attachments: [String]?) -> String`
    - Fetch original message body + attachments
    - Build forwarded message
    - Send via SMTP
  - `moveMessage(id: String, to: String)`
  - `deleteMessage(id: String, permanent: Bool)`
  - `updateFlags(id: String, add: [EmailFlag], remove: [EmailFlag])`
  - `searchMessages(query: String, folder: String?, limit: Int, offset: Int) -> [EmailSummary]`
    - Parse query string into field-specific search terms (from:, subject:, body:, etc.)
    - Search local FTS index for subject/sender matches
    - Fall back to IMAP SEARCH for body content or when local index doesn't have results
  - `listFolders() -> [FolderInfo]`
  - `createFolder(name: String, parent: String?)`
  - `deleteFolder(path: String)`
  - `downloadAttachment(messageId: String, filename: String, destinationPath: String) -> (path: String, size: Int)`
    - Fetch attachment data from IMAP
    - Write to specified filesystem path (create parent dirs if needed)
    - Return path and size

**`Sources/ClawMailCore/Search/SearchEngine.swift`**
- Struct `SearchEngine`
- `parseQuery(_ query: String) -> SearchQuery`
  - Parse the query syntax from the spec:
    - `from:email` → sender filter
    - `to:email` → recipient filter
    - `subject:text` → subject contains
    - `body:text` → body contains
    - `has:attachment` → attachment filter
    - `is:unread`, `is:read`, `is:flagged` → flag filters
    - `before:date`, `after:date` → date ranges
    - `in:folder` → folder filter
    - Free text → subject + body search
    - Multiple terms → AND combination
- `SearchQuery` struct with optional fields for each filter type

### Verification
- Unit test: `EmailCleaner` strips signatures correctly (test with common email patterns)
- Unit test: `EmailCleaner` handles HTML → plain text conversion
- Unit test: `SearchEngine.parseQuery` parses all query syntax variants
- Integration test: `EmailManager` connects, lists messages, reads a message
- Integration test: send → receive round trip
- Integration test: search finds expected messages

---

## Phase 7 — CalDAV Client & Calendar Manager

**Goal**: Implement CalDAV protocol client for calendar and task operations.

### Design Notes

CalDAV is HTTP-based (WebDAV extension). Use `URLSession` or the Hummingbird HTTP client for requests. The protocol uses XML (specifically WebDAV PROPFIND/REPORT/PUT/DELETE with iCalendar payloads).

### Files to Create

**`Sources/ClawMailCore/Calendar/CalDAVClient.swift`**
- Actor `CalDAVClient`
- Initialization: CalDAV base URL, credentials (password or OAuth2 token)
- Connection:
  - `discover(from email: String) -> URL?` — auto-discovery via DNS SRV + well-known URLs
  - `authenticate()` — test authentication with a PROPFIND
- Calendar operations:
  - `listCalendars() -> [CalDAVCalendar]` — PROPFIND on calendar-home-set
  - `getEvents(calendar: String, from: Date, to: Date) -> [String]` — REPORT calendar-query, returns iCalendar strings
  - `createEvent(calendar: String, icalendar: String) -> String` — PUT new .ics resource
  - `updateEvent(calendar: String, uid: String, icalendar: String)` — PUT updated .ics
  - `deleteEvent(calendar: String, uid: String)` — DELETE .ics resource
- Task operations (VTODO):
  - `listTaskLists() -> [CalDAVCalendar]` — task lists are calendars with VTODO support
  - `getTasks(taskList: String, includeCompleted: Bool) -> [String]` — returns iCalendar VTODO strings
  - `createTask(taskList: String, icalendar: String) -> String`
  - `updateTask(taskList: String, uid: String, icalendar: String)`
  - `deleteTask(taskList: String, uid: String)`

- Internal helpers:
  - XML builder for WebDAV requests (PROPFIND, REPORT bodies)
  - XML parser for WebDAV responses (multistatus)
  - iCalendar parser: extract event/task properties from VCALENDAR/VEVENT/VTODO strings
  - iCalendar builder: construct VCALENDAR strings from structured data

**`Sources/ClawMailCore/Calendar/CalendarManager.swift`**
- Actor `CalendarManager`
- Dependencies: `CalDAVClient`
- High-level operations mapping to agent interface:
  - `listCalendars() -> [CalendarInfo]`
  - `listEvents(from: Date, to: Date, calendar: String?) -> [CalendarEvent]`
  - `createEvent(_ request: CreateEventRequest) -> CalendarEvent`
  - `updateEvent(id: String, _ request: UpdateEventRequest) -> CalendarEvent`
  - `deleteEvent(id: String)`
- Convert between CalDAV's iCalendar format and our `CalendarEvent` model

**`Sources/ClawMailCore/Tasks/TaskManager.swift`**
- Actor `TaskManager`
- Dependencies: `CalDAVClient` (shared with CalendarManager)
- Operations:
  - `listTaskLists() -> [TaskList]`
  - `listTasks(taskList: String?, includeCompleted: Bool, sort: SortOrder) -> [TaskItem]`
  - `createTask(_ request: CreateTaskRequest) -> TaskItem`
  - `updateTask(id: String, _ request: UpdateTaskRequest) -> TaskItem`
  - `deleteTask(id: String)`
- Convert between VTODO iCalendar format and our `TaskItem` model

**`Sources/ClawMailCore/Tasks/VTODOParser.swift`**
- iCalendar VTODO specific parsing/building
- Can be folded into the general iCalendar parser in CalDAVClient if cleaner

### Verification
- Unit test: iCalendar parsing and building round-trips correctly
- Unit test: XML WebDAV request construction
- Integration test: list calendars on a real CalDAV server
- Integration test: create → read → update → delete event
- Integration test: create → complete → delete task

---

## Phase 8 — CardDAV Client & Contacts Manager

**Goal**: Implement CardDAV protocol client for contacts operations.

### Files to Create

**`Sources/ClawMailCore/Contacts/CardDAVClient.swift`**
- Actor `CardDAVClient`
- Initialization: CardDAV base URL, credentials
- Connection:
  - `discover(from email: String) -> URL?` — auto-discovery
  - `authenticate()`
- Operations:
  - `listAddressBooks() -> [CardDAVAddressBook]` — PROPFIND
  - `getContacts(addressBook: String, query: String?) -> [String]` — REPORT, returns vCard strings. If query provided, use addressbook-query REPORT with text filter.
  - `createContact(addressBook: String, vcard: String) -> String` — PUT
  - `updateContact(addressBook: String, uid: String, vcard: String)` — PUT
  - `deleteContact(addressBook: String, uid: String)` — DELETE

- Internal helpers:
  - vCard parser: extract structured contact fields from vCard 3.0/4.0 strings
  - vCard builder: construct vCard strings from structured data
  - XML builder/parser for WebDAV requests/responses

**`Sources/ClawMailCore/Contacts/ContactsManager.swift`**
- Actor `ContactsManager`
- Dependencies: `CardDAVClient`
- Operations:
  - `listAddressBooks() -> [AddressBook]`
  - `listContacts(addressBook: String?, query: String?, limit: Int, offset: Int) -> [Contact]`
  - `createContact(_ request: CreateContactRequest) -> Contact`
  - `updateContact(id: String, _ request: UpdateContactRequest) -> Contact`
  - `deleteContact(id: String)`
- Convert between vCard format and our `Contact` model

### Verification
- Unit test: vCard parsing and building
- Integration test: list address books on a real CardDAV server
- Integration test: create → read → update → delete contact
- Integration test: search contacts by name/email

---

## Phase 9 — OAuth2 Manager

**Goal**: Handle OAuth2 authentication flows for Google and Microsoft accounts.

### Files to Create

**`Sources/ClawMailCore/Auth/OAuth2Manager.swift`**
- Actor `OAuth2Manager`
- Dependencies: `KeychainManager`

- Configuration:
  - `OAuthConfig` struct: clientId, clientSecret (optional), authorizationEndpoint, tokenEndpoint, scopes, redirectURI
  - Built-in configs for Google and Microsoft (loaded from bundled config or environment)
  - User-provided client IDs for self-hosted/dev builds (stored in AppConfig)

- Authorization flow:
  - `startAuthorizationFlow(provider: OAuthProvider) -> URL` — returns the authorization URL to open in browser
  - `startCallbackServer() async -> AuthorizationCode` — starts a temporary HTTP server on a random localhost port to receive the OAuth2 callback. Returns the authorization code.
  - `exchangeCodeForTokens(code: String, provider: OAuthProvider) -> OAuthTokens` — POST to token endpoint
  - `saveTokens(accountId: UUID, tokens: OAuthTokens)` — store in Keychain

- Token management:
  - `getAccessToken(accountId: UUID) -> String` — returns valid access token; refreshes if expired
  - `refreshAccessToken(accountId: UUID) -> String` — use refresh token to get new access token
  - `revokeTokens(accountId: UUID)` — revoke with provider and delete from Keychain

- XOAUTH2 support:
  - `buildXOAuth2String(email: String, accessToken: String) -> String` — build the base64-encoded XOAUTH2 authentication string for IMAP/SMTP AUTH

- Google-specific:
  - Authorization endpoint: `https://accounts.google.com/o/oauth2/v2/auth`
  - Token endpoint: `https://oauth2.googleapis.com/token`
  - Scopes: `https://mail.google.com/`, `https://www.googleapis.com/auth/calendar`, `https://www.googleapis.com/auth/contacts`

- Microsoft-specific:
  - Authorization endpoint: `https://login.microsoftonline.com/common/oauth2/v2.0/authorize`
  - Token endpoint: `https://login.microsoftonline.com/common/oauth2/v2.0/token`
  - Scopes: `offline_access IMAP.AccessAsUser.All SMTP.Send Calendars.ReadWrite Contacts.ReadWrite Tasks.ReadWrite`

### Verification
- Integration test: complete OAuth2 flow with Google test account
- Integration test: complete OAuth2 flow with Microsoft test account
- Integration test: token refresh works
- Unit test: XOAUTH2 string building

---

## Phase 10 — Guardrails Engine

**Goal**: Implement configurable guardrails for agent actions.

### Files to Create

**`Sources/ClawMailCore/Guardrails/GuardrailEngine.swift`**
- Actor `GuardrailEngine`
- Dependencies: `AppConfig`, `DatabaseManager` (for approved recipients)
- Main entry point: `check(operation: Operation, account: String) -> GuardrailResult`
  - `GuardrailResult`: `.allowed`, `.blocked(ClawMailError)`, `.pendingApproval(approvalId: Int)`
- Called by the agent interface layer before executing any write operation

**`Sources/ClawMailCore/Guardrails/RateLimiter.swift`**
- Actor `RateLimiter`
- Tracks send counts per time window using the audit log
- `checkSendAllowed(account: String) -> Result<Void, ClawMailError>`
- Uses a sliding window approach: queries audit log for recent sends within each configured window (minute/hour/day)

**`Sources/ClawMailCore/Guardrails/DomainFilter.swift`**
- Struct `DomainFilter`
- `checkRecipients(_ recipients: [EmailAddress], config: GuardrailConfig) -> Result<Void, ClawMailError>`
  - If allowlist configured: all recipients must be in allowed domains
  - If blocklist configured: no recipients may be in blocked domains
  - Allowlist takes precedence if both configured
- `checkFirstTimeRecipient(_ recipients: [EmailAddress], account: String, db: DatabaseManager) -> Result<[EmailAddress], ClawMailError>`
  - Returns list of recipients that need approval
  - Checks against approved_recipients table

### Verification
- Unit test: rate limiter correctly allows/blocks based on configured limits
- Unit test: domain filter handles allowlist, blocklist, and combined scenarios
- Unit test: first-time recipient detection
- Integration test: full guardrail check flow with database

---

## Phase 11 — Sync Engine

**Goal**: Implement email metadata synchronization between IMAP server and local index.

### Files to Create

**`Sources/ClawMailCore/Sync/SyncEngine.swift`**
- Actor `SyncEngine`
- Dependencies: `IMAPClient`, `MetadataIndex`

- Sync operations:
  - `initialSync(account: Account, days: Int)` — fetch metadata for last N days across all folders, populate index
  - `incrementalSync(account: Account, folder: String)` — use CONDSTORE/QRESYNC if available, otherwise UID-based delta
  - `fullReconciliation(account: Account, folder: String)` — compare local UIDs with server, add/remove as needed
  - `handleNewMail(account: String, folder: String)` — called by IDLE monitor when new mail arrives; fetch new message metadata and update index

- Sync logic:
  1. Get local sync state (uidValidity, highestModSeq)
  2. If server uidValidity changed: re-sync folder from scratch (UIDs invalidated)
  3. If server supports CONDSTORE: fetch changes since highestModSeq
  4. Otherwise: fetch all UIDs, compare with local, fetch missing
  5. Update local sync state after successful sync

**`Sources/ClawMailCore/Sync/SyncScheduler.swift`**
- Actor `SyncScheduler`
- Runs periodic full reconciliation on a configurable interval (default: 15 minutes)
- Uses `Task.sleep` in a loop (actor-isolated, cancellable)
- `start(accounts: [Account], interval: TimeInterval)`
- `stop()`
- Triggers `SyncEngine.fullReconciliation` for each account's configured folders

### Verification
- Integration test: initial sync populates metadata index correctly
- Integration test: incremental sync picks up new messages
- Integration test: reconciliation detects and handles deleted messages
- Unit test: sync state comparison logic

---

## Phase 12 — Account Orchestrator

**Goal**: Create the central coordinator that manages all per-account resources and serves as the single entry point for the agent interface layers.

### Files to Create

**`Sources/ClawMailCore/AccountOrchestrator.swift`**
- Actor `AccountOrchestrator`
- This is the **heart of ClawMail**. It owns:
  - `AppConfig` — loaded at startup
  - `DatabaseManager` — single shared database
  - `KeychainManager` / `CredentialStore`
  - Per-account managers: `[String: AccountConnection]` keyed by account label
  - `SyncScheduler`
  - `GuardrailEngine`
  - `AuditLog`

- `AccountConnection` struct (per-account):
  - `emailManager: EmailManager`
  - `calendarManager: CalendarManager?` (nil if CalDAV not configured)
  - `contactsManager: ContactsManager?` (nil if CardDAV not configured)
  - `taskManager: TaskManager?` (nil if CalDAV not configured)
  - `idleMonitor: IMAPIdleMonitor`

- Lifecycle:
  - `start()` — load config, open database, connect all enabled accounts, start sync scheduler, start IDLE monitors
  - `stop()` — disconnect all, stop scheduler, close database
  - `addAccount(_ account: Account)` — save config, connect, start sync
  - `removeAccount(label: String)` — disconnect, purge data, remove config
  - `updateAccount(label: String, _ updates: ...)` — reconfigure

- Agent-facing operations (delegate to per-account managers after guardrail checks):
  - All operations from the spec: email, calendar, contacts, tasks
  - Every write operation is wrapped: guardrail check → execute → audit log
  - Every read operation: execute → audit log (for searches/lists only, not individual reads per spec)

- Agent connection management:
  - `agentConnected: Bool` — tracks if an agent is currently connected
  - `acquireAgentLock(interface: AgentInterface) -> Bool` — single agent at a time
  - `releaseAgentLock()`

- New mail notification:
  - Callback mechanism: when IDLE detects new mail, the orchestrator can notify the connected agent
  - `onNewMail: ((String, String) -> Void)?` — set by MCP server for push notifications

### Verification
- Integration test: full lifecycle — start, connect account, perform operations, stop
- Integration test: guardrail enforcement on send operations
- Integration test: audit log populated after operations
- Unit test: agent lock acquisition and release

---

## Phase 13 — IPC Layer (Unix Domain Socket)

**Goal**: Implement the inter-process communication between the daemon (ClawMailApp) and client processes (CLI, MCP).

### Design Notes

The ClawMailApp runs as the daemon and listens on a Unix domain socket. The CLI and MCP executables are client processes that connect to this socket and issue JSON-RPC 2.0 requests.

### Files to Create

**`Sources/ClawMailCore/IPC/IPCServer.swift`**
- Class `IPCServer` (runs on SwiftNIO EventLoopGroup)
- Socket path: `~/Library/Application Support/ClawMail/clawmail.sock`
- Listens for connections on the Unix domain socket
- Each connection: read JSON-RPC 2.0 requests, dispatch to `AccountOrchestrator`, return JSON-RPC 2.0 responses
- One long-lived agent session at a time (agent lock); concurrent CLI sessions remain allowed
- JSON-RPC 2.0 method names mirror the operation names:
  - `email.list`, `email.read`, `email.send`, `email.reply`, `email.forward`
  - `email.move`, `email.delete`, `email.updateFlags`, `email.search`
  - `email.listFolders`, `email.createFolder`, `email.deleteFolder`
  - `email.downloadAttachment`
  - `calendar.listCalendars`, `calendar.listEvents`, `calendar.createEvent`, `calendar.updateEvent`, `calendar.deleteEvent`
  - `contacts.listAddressBooks`, `contacts.list`, `contacts.create`, `contacts.update`, `contacts.delete`
  - `tasks.listTaskLists`, `tasks.list`, `tasks.create`, `tasks.update`, `tasks.delete`
  - `audit.list`
  - `status`
  - `accounts.list`

- Notification support: server can push JSON-RPC 2.0 notifications to the connected client:
  - `clawmail/newMail` — when IDLE detects new email
  - `clawmail/connectionStatus` — when account connection status changes
  - `clawmail/error` — when an error occurs

**`Sources/ClawMailCore/IPC/IPCClient.swift`**
- Class `IPCClient`
- Connects to the Unix domain socket
- `connect()` → `send(method: String, params: [String: Any]) -> JSONRPCResponse`
- `disconnect()`
- Handles notifications from server (for MCP process to relay)
- If connection fails: return clear error that the daemon is not running

**`Sources/ClawMailCore/IPC/JSONRPCTypes.swift`**
- `JSONRPCRequest` struct: jsonrpc, id, method, params
- `JSONRPCResponse` struct: jsonrpc, id, result (optional), error (optional)
- `JSONRPCNotification` struct: jsonrpc, method, params
- `JSONRPCError` struct: code, message, data

### Verification
- Unit test: JSON-RPC 2.0 serialization/deserialization
- Integration test: server accepts connection, processes request, returns response
- Integration test: server pushes notification to connected client
- Integration test: second connection attempt is rejected

---

## Phase 14 — CLI Interface

**Goal**: Build the `clawmail` command-line tool using Swift Argument Parser.

### Files to Create

**`Sources/ClawMailCLI/CLI.swift`**
- Main entry point using `@main` and `ParsableCommand`
- Top-level command `ClawMail` with subcommands:
  - `email` (with subcommands: list, read, send, reply, forward, move, delete, flag, search, folders, create-folder, delete-folder, download-attachment)
  - `calendar` (with subcommands: list, calendars, create, update, delete)
  - `contacts` (with subcommands: list, address-books, create, update, delete)
- `tasks` (with subcommands: list, task-lists, create, update, delete)
  - `accounts` (with subcommands: list)
  - `audit` (with subcommands: list)
  - `recipients` (with subcommands: list, pending, approve, reject, remove)
  - `status`

MCP is implemented as a separate executable target (`ClawMailMCP` / `clawmail-mcp`) rather than a `clawmail mcp` subcommand.

**`Sources/ClawMailCLI/Commands/EmailCommands.swift`**
- Implementation of all email subcommands
- Each command:
  1. Connects to daemon via `IPCClient`
  2. Sends appropriate JSON-RPC request
  3. Formats response based on `--format` flag
  4. Outputs to stdout
  5. Exits with appropriate status code

- Flag patterns:
  - `--account` (required when multiple accounts, error if omitted)
  - `--format=json|text|csv` (default: json)
  - `--limit`, `--offset` for pagination
  - Command-specific flags as defined in spec

**`Sources/ClawMailCLI/Commands/CalendarCommands.swift`**
- Calendar subcommands
- Date inputs accept ISO 8601 format

**`Sources/ClawMailCLI/Commands/ContactsCommands.swift`**
- Contacts subcommands

**`Sources/ClawMailCLI/Commands/TasksCommands.swift`**
- Tasks subcommands

**`Sources/ClawMailCLI/Commands/AccountCommands.swift`**
- `accounts list` — list configured accounts with connection status

**`Sources/ClawMailCLI/Commands/AuditCommands.swift`**
- `audit list` with filtering flags: `--account`, `--operation`, `--from`, `--to`, `--limit`, `--offset`

**`Sources/ClawMailCLI/Commands/StatusCommand.swift`**
- Show daemon status, connected accounts, agent connection state, API port

**`Sources/ClawMailCLI/Output/Formatters.swift`**
- `OutputFormatter` protocol with `format(_ value: Codable) -> String`
- `JSONFormatter` — pretty-printed JSON (default)
- `TextFormatter` — human-readable table format
- `CSVFormatter` — for tabular data (message lists, audit entries)

### Verification
- Test: `clawmail status` returns daemon status
- Test: `clawmail email list --account=test --format=json` returns valid JSON
- Test: `clawmail email send` with all required flags sends successfully
- Test: `clawmail --help` and all subcommand `--help` produce useful output
- Test: missing `--account` flag returns error listing available accounts
- Test: error responses are properly formatted

---

## Phase 15 — MCP Server

**Goal**: Implement the MCP stdio server that Claude Code and other MCP clients connect to.

### Design Notes

MCP (Model Context Protocol) uses JSON-RPC 2.0 over stdin/stdout. The server declares its capabilities (tools, resources, notifications), and the client invokes tools and reads resources.

The MCP server process is launched by the MCP client (e.g., Claude Code). It connects to the running ClawMail daemon via the Unix domain socket (IPC) to perform operations.

### Files to Create

**`Sources/ClawMailMCP/MCPServer.swift`**
- Main MCP server implementation
- Reads JSON-RPC requests from stdin, writes responses to stdout
- On startup:
  1. Connect to daemon via `IPCClient`
  2. Respond to `initialize` with server capabilities
  3. Enter request loop

- Server capabilities declaration:
  - Tools: all agent operations
  - Resources: accounts list, account status, folder listing
  - Notifications: newMail, connectionStatus, error

- Request handling loop:
  - Read line from stdin
  - Parse as JSON-RPC 2.0 request
  - Dispatch to appropriate handler
  - Send JSON-RPC 2.0 response to stdout

- Notification relay:
  - Listen for notifications from daemon via IPC
  - Forward as MCP notifications to stdout

**`Sources/ClawMailMCP/Tools/EmailTools.swift`**
- MCP tool definitions for all email operations
- Each tool has:
  - `name`: e.g., `"email_list"`, `"email_read"`, `"email_send"`
  - `description`: clear description of what the tool does
  - `inputSchema`: JSON Schema defining the tool's parameters
  - `handler`: function that translates MCP tool call → IPC request → MCP tool result

- Tools:
  - `email_list` — list messages in a folder
  - `email_read` — read a specific message
  - `email_send` — send a new email
  - `email_reply` — reply to a message
  - `email_forward` — forward a message
  - `email_move` — move a message to another folder
  - `email_delete` — delete a message
  - `email_update_flags` — update message flags
  - `email_search` — search messages
  - `email_list_folders` — list folders
  - `email_create_folder` — create a folder
  - `email_delete_folder` — delete a folder
  - `email_download_attachment` — download an attachment

**`Sources/ClawMailMCP/Tools/CalendarTools.swift`**
- MCP tools for calendar operations:
  - `calendar_list_calendars`, `calendar_list_events`, `calendar_create_event`, `calendar_update_event`, `calendar_delete_event`

**`Sources/ClawMailMCP/Tools/ContactsTools.swift`**
- MCP tools for contacts operations:
  - `contacts_list_address_books`, `contacts_list`, `contacts_create`, `contacts_update`, `contacts_delete`

**`Sources/ClawMailMCP/Tools/TasksTools.swift`**
- MCP tools for tasks operations:
  - `tasks_list_task_lists`, `tasks_list`, `tasks_create`, `tasks_update`, `tasks_delete`

**`Sources/ClawMailMCP/Resources/AccountResources.swift`**
- MCP resource definitions:
  - `clawmail://accounts` — list all accounts
  - `clawmail://accounts/{label}/status` — account connection status and stats
  - `clawmail://accounts/{label}/folders` — folder listing with unread counts

**`Sources/ClawMailMCP/Notifications/MailNotifier.swift`**
- Listens for IPC notifications from daemon
- Converts to MCP notification format
- Writes to stdout as JSON-RPC 2.0 notifications

### Verification
- Test: MCP initialization handshake completes correctly
- Test: tool listing returns all tools with valid JSON Schemas
- Test: `email_list` tool returns messages in correct MCP format
- Test: `email_send` tool sends email and returns result
- Test: notifications are forwarded from daemon to MCP client
- Test: configure in Claude Code's `.mcp.json` and verify tools appear

---

## Phase 16 — REST API Server

**Goal**: Implement the localhost REST API with API key authentication.

### Files to Create

**`Sources/ClawMailAPI/APIServer.swift`**
- Hummingbird application setup
- Bind to `127.0.0.1` on configured port (default: 24601)
- Register all route groups
- Configure JSON encoding/decoding
- Startup/shutdown lifecycle tied to the daemon

**`Sources/ClawMailAPI/Middleware/AuthMiddleware.swift`**
- Hummingbird middleware
- Extract `Authorization: Bearer <key>` header
- Compare against stored API key (from Keychain)
- Return 401 if missing or invalid
- Skip auth for `/api/v1/status` (allows health checks)

**`Sources/ClawMailAPI/Routes/EmailRoutes.swift`**
- Route group under `/api/v1/email`
- Endpoints (see spec for full list):
  - `GET /` — list messages (query params: account, folder, limit, offset)
  - `GET /:messageId` — read message (query param: account)
  - `POST /send` — send message (JSON body)
  - `POST /reply` — reply to message (JSON body)
  - `POST /forward` — forward message (JSON body)
  - `PATCH /:messageId` — move or update flags (JSON body)
  - `DELETE /:messageId` — delete message (query params: account, permanent)
  - `GET /search` — search messages (query params: account, q, folder, limit, offset)
  - `GET /folders` — list folders (query param: account)
  - `POST /folders` — create folder (JSON body)
  - `DELETE /folders/:path` — delete folder (query param: account)
  - `GET /:messageId/attachments/:filename` — download attachment (query params: account, destination)

- Each route:
  1. Parse request parameters
  2. Call `AccountOrchestrator` method
  3. Serialize result as JSON response
  4. Handle errors → structured JSON error response

**`Sources/ClawMailAPI/Routes/CalendarRoutes.swift`**
- Route group under `/api/v1/calendar`
- Standard REST endpoints for events and calendar listing

**`Sources/ClawMailAPI/Routes/ContactsRoutes.swift`**
- Route group under `/api/v1/contacts`
- Standard REST endpoints for contacts and address book listing

**`Sources/ClawMailAPI/Routes/TasksRoutes.swift`**
- Route group under `/api/v1/tasks`
- Standard REST endpoints for tasks and task list management

**`Sources/ClawMailAPI/Routes/AuditRoutes.swift`**
- `GET /api/v1/audit` — list audit entries with filtering

**`Sources/ClawMailAPI/Routes/StatusRoutes.swift`**
- `GET /api/v1/status` — daemon status (no auth required)
- `GET /api/v1/accounts` — list accounts with connection status

**`Sources/ClawMailAPI/Webhook/WebhookManager.swift`**
- Actor `WebhookManager`
- If webhook URL is configured in settings:
  - On new email: POST notification to webhook URL
  - Payload: same as MCP notification format
  - Retry with exponential backoff on failure (max 3 retries)
  - Log webhook delivery failures

### Verification
- Test: API key authentication blocks unauthorized requests
- Test: all endpoints return correct JSON structures
- Test: `curl http://127.0.0.1:24601/api/v1/status` returns status without auth
- Test: email CRUD operations work via REST
- Test: webhook fires on new email (use a local HTTP listener)
- Test: error responses match spec format

---

## Phase 17 — macOS App (SwiftUI)

**Goal**: Build the menu bar application with settings window.

### Files to Create

**`Sources/ClawMailApp/ClawMailApp.swift`**
- `@main` App struct
- `MenuBarExtra` for the menu bar icon (macOS 13+)
- WindowGroup for the Settings window (opened on demand)
- On launch:
  1. Initialize `AccountOrchestrator`
  2. Start the orchestrator (connects accounts, starts sync, starts IDLE)
  3. Start `IPCServer` (Unix domain socket)
  4. Start `APIServer` (REST API on localhost)
  5. Show menu bar icon
  6. If no accounts configured, open Settings window

**`Sources/ClawMailApp/MenuBar/MenuBarManager.swift`**
- Observable class managing menu bar state
- Properties: connection status per account, agent connected flag, last activity string, unread counts
- Updates from `AccountOrchestrator` notifications

**`Sources/ClawMailApp/MenuBar/StatusMenu.swift`**
- SwiftUI view for the menu bar dropdown
- Layout matching the spec:
  - Account status lines with indicators
  - Last activity line
  - Unread counts
  - Separator
  - "Settings..." menu item (opens Settings window)
  - "Activity Log..." menu item (opens Settings window to Activity Log tab)
  - Separator
  - "Quit ClawMail" menu item

- Menu bar icon rendering:
  - Use SF Symbols or custom asset
  - Normal: outline envelope
  - Active (agent connected): filled envelope
  - Warning: envelope with yellow dot
  - Error: envelope with red dot

**`Sources/ClawMailApp/Settings/SettingsWindow.swift`**
- `Window` or `Settings` scene
- Tab-based layout using `TabView` with sidebar style
- Tabs: Accounts, Guardrails, API, Activity Log, General

**`Sources/ClawMailApp/Settings/AccountsTab.swift`**
- List of configured accounts in a sidebar/list
- Per-account detail view showing:
  - Label, email, display name (editable)
  - Server configuration (IMAP/SMTP host/port, CalDAV/CardDAV URLs)
  - Connection status indicator
  - "Test Connection" button
  - "Remove Account" button with confirmation
- "Add Account" button at bottom → opens `AccountSetupView`

**`Sources/ClawMailApp/Account/AccountSetupView.swift`**
- Step-by-step account setup sheet/window:
  - Step 1: Provider selection (Google, Microsoft, Other)
  - Step 2a (Google/Microsoft): OAuth2 flow → opens browser
  - Step 2b (Other): Manual form — email, IMAP host/port, SMTP host/port, username, password, CalDAV URL, CardDAV URL
  - Step 3: Connection test (progress indicator, success/failure)
  - Step 4: Account label entry
  - Step 5: Done → account appears in list

**`Sources/ClawMailApp/Account/OAuthFlowView.swift`**
- SwiftUI view shown during OAuth2 flow
- "Waiting for authorization..." with a spinner
- "Open Browser Again" button if user closed it
- Cancel button
- Completion → dismisses and shows test connection result

**`Sources/ClawMailApp/Account/ConnectionTestView.swift`**
- Tests IMAP, SMTP, CalDAV, CardDAV connections sequentially
- Shows progress for each with checkmarks or error messages
- "Back" to fix settings, "Save" when all pass

**`Sources/ClawMailApp/Settings/GuardrailsTab.swift`**
- Toggle + configuration for each guardrail:
  - Send rate limits: toggle, then fields for per-minute/per-hour/per-day limits
  - Domain allowlist: toggle, then editable list of domains
  - Domain blocklist: toggle, then editable list of domains
  - First-time recipient approval: toggle
  - Below: list of approved recipients with ability to remove
  - Below: list of pending approvals with approve/reject buttons

**`Sources/ClawMailApp/Settings/APITab.swift`**
- REST API configuration:
  - Port number field (default 24601)
  - API key display (masked with eye toggle) + copy button + regenerate button
  - MCP server status (running/stopped)
  - CLI path display (`/usr/local/bin/clawmail`)
  - Webhook URL field
  - "Copy MCP Config" button — copies the `.mcp.json` snippet to clipboard

**`Sources/ClawMailApp/Settings/ActivityLogTab.swift`**
- Scrollable table of audit log entries
- Columns: timestamp, interface, operation, account, result
- Expandable rows to show full parameters/details
- Filter bar: account dropdown, operation dropdown, date range picker
- Search field (searches across all columns)
- Export button: JSON or CSV
- Auto-refresh toggle (polls audit log for new entries)

**`Sources/ClawMailApp/Settings/GeneralTab.swift`**
- Launch at login toggle (manages LaunchAgent plist)
- Initial sync period (days, default: 30)
- Sync interval (minutes, default: 15)
- Audit log retention (days, default: 90)
- IMAP IDLE folders (editable list, default: ["INBOX"])
- "Reset All Settings" button with confirmation

### Verification
- Test: app launches as menu bar app (no Dock icon)
- Test: menu bar icon appears and dropdown shows correct status
- Test: Settings window opens from menu bar
- Test: account setup flow (manual IMAP/SMTP) completes successfully
- Test: OAuth2 flow opens browser and completes
- Test: guardrail toggles persist across app restart
- Test: activity log shows recent operations
- Test: API tab displays API key and copies to clipboard

---

## Phase 18 — Launch Agent & Installation

**Goal**: Set up auto-launch at login and prepare for Homebrew distribution.

### Files to Create

**`Resources/com.clawmail.agent.plist`**
- LaunchAgent plist as specified in the spec
- Label: `com.clawmail.agent`
- Program: `/Applications/ClawMail.app/Contents/MacOS/ClawMailApp`
- RunAtLoad: true
- KeepAlive: true

**General Tab integration** (in `GeneralTab.swift` from Phase 17):
- "Launch at Login" toggle should:
  - On enable: copy plist to `~/Library/LaunchAgents/`, run `launchctl load`
  - On disable: run `launchctl unload`, remove plist

Launch-at-login starts the app bundle executable directly instead of a CLI daemon subcommand.

**Homebrew Cask formula** (create `HomebrewFormula/clawmail.rb` for reference):
```ruby
cask "clawmail" do
  version "0.1.0"
  sha256 "..." # computed at release time

  url "https://github.com/<org>/ClawMail/releases/download/v#{version}/ClawMail-#{version}.dmg"
  name "ClawMail"
  desc "Agent-first email client for macOS"
  homepage "https://github.com/<org>/ClawMail"

  app "ClawMail.app"
  binary "#{appdir}/ClawMail.app/Contents/MacOS/ClawMailCLI", target: "/usr/local/bin/clawmail"
  binary "#{appdir}/ClawMail.app/Contents/MacOS/ClawMailMCP", target: "/usr/local/bin/clawmail-mcp"

  postflight do
    # App installation is sufficient; binary stanzas expose the CLI tools
  end

  uninstall launchctl: "com.clawmail.agent",
            quit: "com.clawmail.app"

  zap trash: [
    "~/Library/Application Support/ClawMail",
    "~/Library/LaunchAgents/com.clawmail.agent.plist",
  ]
end
```

### Build & Release Pipeline

The project should include a `Makefile` or build script:

```makefile
# Build the app bundle
build:
	swift build -c release
	# Create .app bundle structure
	# Copy executables into Contents/MacOS/
	# Copy Info.plist and resources into Contents/
	# Code sign with Developer ID

# Create DMG for distribution
dmg: build
	# Create DMG from .app bundle
	# Notarize with Apple

# Run tests
test:
	swift test

# Install locally (development)
install: build
	cp -r build/ClawMail.app /Applications/
	ln -sf /Applications/ClawMail.app/Contents/MacOS/ClawMailCLI /usr/local/bin/clawmail
```

### Verification
- Test: `make build` produces a valid .app bundle
- Test: LaunchAgent installs and loads correctly
- Test: app starts at login after LaunchAgent installation
- Test: `clawmail` CLI symlink works
- Test: Homebrew formula structure is valid

---

## Phase 19 — Integration Testing & Polish

**Goal**: End-to-end testing across all interfaces and final polish.

### Test Scenarios

**Setup**: Configure a test email account (create a temporary Gmail or use a local IMAP server like Greenmail or hMailServer for automated testing).

1. **First run flow**:
   - Launch app → Settings opens → add account → connection test → account connected → menu bar shows status

2. **Email via CLI**:
   - `clawmail email list --account=test` → returns messages
   - `clawmail email send --account=test --to=... --subject=... --body=...` → sends, appears in sent folder
   - `clawmail email search --account=test --query="subject:test"` → finds the sent email

3. **Email via MCP**:
   - Configure in `.mcp.json`, connect Claude Code
   - Agent uses `email_list` tool → sees messages
   - Agent uses `email_send` tool → email is sent
   - New email arrives → MCP notification pushed to agent

4. **Email via REST**:
   - `curl -H "Authorization: Bearer <key>" http://127.0.0.1:24601/api/v1/email?account=test` → returns messages
   - POST to send endpoint → email sent
   - Webhook fires on new mail

5. **Calendar via all interfaces**:
   - Create event → list events → update event → delete event
   - Verify on server (e.g., check Google Calendar)

6. **Contacts via all interfaces**:
   - Create contact → search contacts → update contact → delete contact

7. **Tasks via all interfaces**:
   - Create task → list tasks → complete task → delete task

8. **Guardrails**:
   - Enable rate limiting → exceed limit → verify error returned
   - Enable domain blocklist → send to blocked domain → verify blocked
   - Enable first-time recipient approval → send to new address → verify held

9. **Audit log**:
   - Perform various operations → verify audit log captures all
   - View in Settings window → verify filterable

10. **Edge cases**:
    - Multiple accounts configured → operations require --account flag
    - Account disconnects → operations return ACCOUNT_DISCONNECTED error
    - Daemon not running → CLI returns clear error message
    - Two agents try to connect simultaneously → second is rejected

### Polish Items

- Error messages are clear and actionable
- CLI help text is complete for all commands
- MCP tool descriptions are clear enough for an LLM to use correctly
- Menu bar icon updates in real-time
- Settings window is responsive and saves changes immediately
- Audit log auto-scrolls and shows new entries
- Memory usage is reasonable (< 100MB typical)

---

## Build Sequence Summary

| Phase | Name | Depends On | Estimated Complexity |
|-------|------|-----------|---------------------|
| 0 | Project Scaffolding | — | Low |
| 1 | Core Data Models | 0 | Low |
| 2 | Credential Storage | 0, 1 | Low |
| 3 | SQLite Database | 0, 1 | Medium |
| 4 | IMAP Client | 0 | High |
| 5 | SMTP Client | 0 | Medium |
| 6 | Email Manager & Cleaner | 1, 3, 4, 5 | Medium |
| 7 | CalDAV & Calendar | 1 | Medium |
| 8 | CardDAV & Contacts | 1 | Medium |
| 9 | OAuth2 Manager | 2 | Medium |
| 10 | Guardrails Engine | 1, 3 | Low |
| 11 | Sync Engine | 3, 4 | Medium |
| 12 | Account Orchestrator | 2, 3, 6, 7, 8, 9, 10, 11 | High |
| 13 | IPC Layer | 12 | Medium |
| 14 | CLI Interface | 13 | Medium |
| 15 | MCP Server | 13 | Medium |
| 16 | REST API | 12 | Medium |
| 17 | macOS App (SwiftUI) | 12, 13, 16 | High |
| 18 | Launch Agent & Install | 14, 17 | Low |
| 19 | Integration Testing | All | Medium |

**Parallelization opportunities**:
- Phases 4, 5, 7, 8, 9 can be developed in parallel (independent protocol clients)
- Phases 14, 15, 16 can be developed in parallel (independent interface layers, all depend on Phase 13)
- Phase 10 can be developed in parallel with 4–9

**Critical path**: 0 → 1 → 3 → 4 → 6 → 11 → 12 → 13 → 17

---

## Appendix: Key Decisions for Implementers

1. **IMAP library choice**: If `swift-nio-imap` works well, use it. Otherwise, implement IMAP commands directly on SwiftNIO. Don't spend excessive time trying to make a broken library work.

2. **CalDAV/CardDAV XML**: These protocols use verbose XML. Consider using `Foundation`'s `XMLParser` or a lightweight Swift XML package. Don't pull in a heavy dependency for this.

3. **iCalendar/vCard parsing**: These formats are text-based and well-documented. Implementing a basic parser is likely less effort than finding and integrating a Swift library. Focus on the fields the spec requires, not full RFC compliance.

4. **MCP protocol**: Implement directly as JSON-RPC 2.0 over stdio. The protocol is simple enough that a full SDK is unnecessary. Focus on correct tool definitions with accurate JSON Schemas — this is what makes the tools usable by AI agents.

5. **Error propagation**: Every layer should translate errors into `ClawMailError` codes. Never leak protocol-level errors (IMAP BAD response, HTTP 500) to the agent — always wrap in the spec's error format.

6. **Testing accounts**: For development, use a free email provider that supports app passwords and has CalDAV/CardDAV (Fastmail trial, or a local test server). Google requires OAuth2 app registration which takes time.

7. **Concurrency safety**: Use actors throughout. The `AccountOrchestrator` is the main synchronization point. Don't use locks or dispatch queues — Swift actors handle this correctly.

---

## Appendix: Agent Team Orchestration

This project is designed to be built by 2–3 agents working concurrently. The orchestrating agent (the one reading this document) should use sub-agents for parallel workstreams while managing the critical path itself.

### Principles

1. **Shared models are the contract.** Phase 1 (Core Data Models) must be completed first by a single agent. These types define the interfaces between all modules. Once models compile, parallel work can begin.
2. **One agent owns the critical path.** The main agent handles: Phase 0 → 1 → 3 → 6 → 11 → 12 → 13. This is the sequence where each phase directly feeds the next.
3. **Sub-agents work on independent modules.** Protocol clients (IMAP, SMTP, CalDAV, CardDAV, OAuth2) and interface layers (CLI, MCP, REST) are highly independent once their input/output types are defined.
4. **Integrate frequently.** After each parallel batch completes, the main agent should run `swift build` to verify everything compiles together before starting the next batch.

### Execution Plan

```
Timeline  Main Agent                    Sub-Agent A              Sub-Agent B
────────  ──────────────────────────    ─────────────────────    ─────────────────────
Batch 1   Phase 0: Scaffolding
          Phase 1: Core Data Models
          (both must finish before parallel work begins)

Batch 2   Phase 3: SQLite Database      Phase 4: IMAP Client     Phase 7: CalDAV Client
          Phase 2: Credential Storage                            Phase 8: CardDAV Client
          Phase 10: Guardrails Engine

          ── swift build checkpoint ──

Batch 3   Phase 6: Email Manager        Phase 5: SMTP Client     Phase 9: OAuth2 Manager
          (depends on Ph 3,4 — wait     (independent)            (depends on Ph 2)
           for Sub-Agent A to finish
           IMAP before starting)

          ── swift build checkpoint ──

Batch 4   Phase 11: Sync Engine
          Phase 12: Account Orchestrator
          (these are integration layers — main agent should handle them
           since they tie together everything from Batches 2–3)

          ── swift build checkpoint ──

Batch 5   Phase 13: IPC Layer           Phase 14: CLI            Phase 15: MCP Server
          (main agent builds IPC        (after IPC compiles,     (after IPC compiles,
           first, then sub-agents        sub-agent takes over)    sub-agent takes over)
           take CLI + MCP)
                                        Phase 16: REST API
                                        (after CLI is done or
                                         in parallel with MCP)

          ── swift build checkpoint ──

Batch 6   Phase 17: macOS App (SwiftUI)
          Phase 18: Launch Agent & Install
          (main agent — UI work is hard to parallelize)

Batch 7   Phase 19: Integration Testing
          (all agents can run different test scenarios in parallel)
```

### Sub-Agent Task Descriptions

When spawning a sub-agent for a phase, provide it with:

1. **The phase description** from this blueprint (copy the full phase section)
2. **The relevant model files** — point to `Sources/ClawMailCore/Models/` and tell it to read the types it needs
3. **The target directory** — which `Sources/` subdirectory to work in
4. **The verification criteria** — what "done" looks like
5. **Instruction to NOT modify shared files** — sub-agents should only create/modify files within their assigned directory. If they need a change to a shared model, they should report back rather than making the change.

Example sub-agent prompt:
```
Implement Phase 4 (IMAP Client) for the ClawMail project.

Read the full phase description in BLUEPRINT.md under "Phase 4 — IMAP Client".
Read the data models in Sources/ClawMailCore/Models/ — especially Email.swift and Account.swift.
Read Package.swift for available dependencies.

Create all files under Sources/ClawMailCore/Email/ as described in the blueprint.
Do NOT modify any files outside of Sources/ClawMailCore/Email/.

When done, verify that `swift build` compiles successfully.
```

### Handling Integration Conflicts

If a sub-agent discovers that a shared model needs a change (e.g., `Account.swift` is missing a field), it should:
1. Add a `// TODO: Account model needs field X for Y` comment in its own code
2. Use a temporary local type or extension as a workaround
3. Report the needed change when it completes

The main agent then makes the shared model change and verifies all modules still compile.

### Worktree Strategy

Each sub-agent can optionally work in a git worktree (using the `isolation: "worktree"` parameter) for maximum isolation. The main agent then merges completed worktrees. However, for this project, **working in the same directory is recommended** since sub-agents operate in different subdirectories and Swift Package Manager handles the build graph. Use worktrees only if merge conflicts become a problem.

---

## Appendix: Local Test Server Setup

Use Docker Compose to run local IMAP/SMTP servers for automated testing during development. This eliminates the need for real email accounts during the build.

### Docker Compose File

Create `docker-compose.yml` in the project root:

```yaml
version: "3.8"

services:
  # GreenMail — lightweight test mail server
  # Supports IMAP, SMTP, POP3 with no configuration
  greenmail:
    image: greenmail/standalone:2.1.0
    ports:
      - "3025:3025"   # SMTP
      - "3110:3110"   # POP3
      - "3143:3143"   # IMAP
      - "3465:3465"   # SMTPS
      - "3993:3993"   # IMAPS
      - "8080:8080"   # API (for test setup)
    environment:
      - GREENMAIL_OPTS=-Dgreenmail.setup.test.all -Dgreenmail.hostname=0.0.0.0 -Dgreenmail.auth.disabled
      # GreenMail auto-creates accounts on first login
      # Use any email/password combination — account is created on the fly
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/user"]
      interval: 10s
      timeout: 5s
      retries: 3

  # Radicale — lightweight CalDAV/CardDAV server
  radicale:
    image: tomsquest/docker-radicale:3.2.3.1
    ports:
      - "5232:5232"   # CalDAV/CardDAV (HTTP)
    volumes:
      - radicale_data:/data
    environment:
      # No authentication for testing
      - RADICALE_AUTH_TYPE=none

volumes:
  radicale_data:
```

### Test Account Configuration

For tests, use these connection details:

```swift
// Test constants — Sources/ClawMailCoreTests/TestConfig.swift
struct TestConfig {
    // GreenMail IMAP
    static let imapHost = "127.0.0.1"
    static let imapPort = 3143          // IMAP (unencrypted, OK for local testing)
    static let imapsPort = 3993         // IMAPS

    // GreenMail SMTP
    static let smtpHost = "127.0.0.1"
    static let smtpPort = 3025          // SMTP (unencrypted, OK for local testing)
    static let smtpsPort = 3465         // SMTPS

    // GreenMail auto-creates accounts on first login
    static let testEmail = "agent@test.clawmail.local"
    static let testPassword = "testpass123"
    static let testEmail2 = "other@test.clawmail.local"
    static let testPassword2 = "testpass456"

    // Radicale CalDAV/CardDAV
    static let caldavURL = URL(string: "http://127.0.0.1:5232/agent/calendar.ics/")!
    static let carddavURL = URL(string: "http://127.0.0.1:5232/agent/contacts.vcf/")!
}
```

### Test Lifecycle

Tests should:
1. Check that Docker containers are running (skip with a clear message if not)
2. Use unique email addresses or subjects per test to avoid interference
3. Clean up created resources after each test (delete sent emails, events, contacts, tasks)

### Running Tests

```bash
# Start test servers
docker compose up -d

# Wait for health check
docker compose ps  # verify "healthy" status

# Run tests
swift test

# Stop test servers
docker compose down
```

### CI Integration

For GitHub Actions or similar CI, add the Docker Compose setup as a service:

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Start test servers
        run: docker compose up -d --wait
      - name: Build
        run: swift build
      - name: Test
        run: swift test
      - name: Stop test servers
        run: docker compose down
```

Note: macOS GitHub Actions runners have Docker available via colima or similar. If Docker is unavailable, tests that require the mail server should be skipped gracefully using a `XCTSkipIf` check.

---

## Appendix: Implementation Pitfalls & Guidance

These are specific areas where an implementing agent is likely to get stuck. Address them proactively.

### 1. Swift Package Version Pinning

Pin all dependencies to specific version ranges in `Package.swift` to avoid breaking changes. As of early 2026, recommended versions:

```swift
dependencies: [
    // Networking
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),

    // Database
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),

    // CLI
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),

    // HTTP Server (for REST API)
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),

    // HTML Parsing
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),

    // Keychain
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
]
```

**Important**: Verify these versions exist and are compatible before using them. If a package has moved or changed its API, the agent should check the package's GitHub page and adjust accordingly. Do not waste time fighting a broken dependency — if a package doesn't work, implement the functionality directly (especially for IMAP/SMTP where Swift libraries are limited).

### 2. macOS Entitlements & Signing

The app needs specific entitlements to function correctly. Create `Sources/ClawMailApp/Resources/ClawMail.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Network access for IMAP/SMTP/CalDAV/CardDAV -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- Local network server for REST API -->
    <key>com.apple.security.network.server</key>
    <true/>

    <!-- Keychain access for credential storage -->
    <key>com.apple.security.keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.clawmail</string>
    </array>
</dict>
</plist>
```

For **development builds** (unsigned), most of these work without explicit entitlements since the app isn't sandboxed. But the entitlements file must be in place for signed/notarized release builds.

For the **CLI and MCP executables**: these don't need separate entitlements since they communicate with the daemon (which handles all network/keychain access) via the Unix domain socket.

### 3. CLI ↔ Daemon Detection

The CLI needs to know if the daemon is running before attempting IPC. Implement this detection in `IPCClient`:

```
1. Check if the socket file exists at ~/Library/Application Support/ClawMail/clawmail.sock
2. If it doesn't exist → daemon is not running
3. If it exists → attempt to connect
4. If connection refused → socket is stale (daemon crashed). Delete the stale socket file.
5. If connected → send a "ping" JSON-RPC request to verify the daemon is responsive
```

**Error message when daemon is not running**:
```
Error: ClawMail daemon is not running.

Start it with one of:
  - Open ClawMail.app from Applications
  - Enable Launch at Login in ClawMail Settings
```

The daemon should also clean up the socket file on graceful shutdown. Register a signal handler for SIGTERM and SIGINT that:
1. Closes all IMAP connections
2. Stops the REST API server
3. Removes the socket file
4. Exits cleanly

### 4. Graceful Degradation for CalDAV/CardDAV

Not every account will have CalDAV/CardDAV configured (especially generic IMAP accounts where the user didn't provide URLs). Handle this consistently:

**In `AccountOrchestrator`**:
- When an account's `caldavURL` is nil, `calendarManager` and `taskManager` should be nil for that account
- When an account's `carddavURL` is nil, `contactsManager` should be nil for that account

**In all agent interfaces** (MCP, CLI, REST):
- If a calendar/contacts/tasks operation is requested for an account without the required protocol:
  - Return `ClawMailError.calendarNotAvailable` or `ClawMailError.contactsNotAvailable`
  - Error message should say: "CalDAV is not configured for account 'work'. Add a CalDAV URL in Settings → Accounts → work."
- The `accounts list` output should indicate which capabilities each account has:
  ```json
  {
    "label": "work",
    "email": "agent@company.com",
    "status": "connected",
    "capabilities": ["email", "calendar", "contacts", "tasks"]
  }
  ```
  vs.
  ```json
  {
    "label": "personal",
    "email": "agent@gmail.com",
    "status": "connected",
    "capabilities": ["email"]
  }
  ```

**In the Settings UI**:
- CalDAV/CardDAV URL fields should be clearly optional
- Show a subtle indicator on the Accounts list showing which capabilities are active
- Auto-discovery should be attempted when an account is added (even for generic IMAP) — if it finds CalDAV/CardDAV endpoints, fill them in automatically

### 5. IMAP Connection Edge Cases

IMAP is the most complex protocol in the project. Watch for these:

- **IMAP literal handling**: Some servers use literals (`{N}\r\n` followed by N bytes) in responses. The parser must handle these, especially for large message bodies.
- **IMAP UTF-7 folder names**: IMAP uses a modified UTF-7 encoding for folder names with non-ASCII characters. Implement encoding/decoding.
- **IMAP IDLE reconnection**: After 29 minutes, re-issue IDLE. If the connection drops during IDLE, reconnect and re-issue. Don't let a dropped IDLE connection silently stop working.
- **IMAP concurrent operations**: An IMAP connection processes one command at a time (tagged responses). Don't try to pipeline commands unless the server advertises PIPELINING capability. The actor model naturally serializes access, which is correct.
- **IMAP MOVE vs COPY+DELETE**: Not all servers support the MOVE command (RFC 6851). Check for MOVE capability, fall back to COPY + STORE \Deleted + EXPUNGE.
- **Large mailboxes**: When doing initial sync on a folder with 100K+ messages, don't try to fetch all metadata at once. Batch FETCH commands in groups of 500-1000 UIDs.

### 6. MCP Tool Descriptions

The quality of MCP tool descriptions directly determines how well AI agents can use ClawMail. Each tool description must:

- State clearly what the tool does in one sentence
- List all parameters with types and what they control
- Describe the return value
- Mention any prerequisites (e.g., "account must be specified")
- Include an example use case

**Good example**:
```json
{
  "name": "email_send",
  "description": "Send a new email from the specified account. Supports plain text and HTML bodies, CC/BCC recipients, and file attachments from the local filesystem.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "account": {
        "type": "string",
        "description": "Account label to send from (e.g., 'work'). Run accounts_list to see available accounts."
      },
      "to": {
        "type": "array",
        "items": {"type": "string"},
        "description": "Recipient email addresses"
      },
      "subject": {
        "type": "string",
        "description": "Email subject line"
      },
      "body": {
        "type": "string",
        "description": "Plain text email body"
      },
      "body_html": {
        "type": "string",
        "description": "Optional HTML email body. If omitted, only plain text is sent."
      },
      "cc": {
        "type": "array",
        "items": {"type": "string"},
        "description": "CC recipient email addresses"
      },
      "bcc": {
        "type": "array",
        "items": {"type": "string"},
        "description": "BCC recipient email addresses"
      },
      "attachments": {
        "type": "array",
        "items": {"type": "string"},
        "description": "Absolute file paths to attach to the email"
      },
      "in_reply_to": {
        "type": "string",
        "description": "Message ID of the email this is replying to (sets In-Reply-To header). Use email_reply for full reply functionality."
      }
    },
    "required": ["account", "to", "subject", "body"]
  }
}
```

**Bad example** (too vague for an LLM):
```json
{
  "name": "email_send",
  "description": "Send an email",
  "inputSchema": {
    "type": "object",
    "properties": {
      "account": {"type": "string"},
      "to": {"type": "array"},
      "subject": {"type": "string"},
      "body": {"type": "string"}
    }
  }
}
```
