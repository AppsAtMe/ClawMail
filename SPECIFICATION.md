# ClawMail — Agent-First Email Client for macOS

## Overview

ClawMail is a macOS-native application that gives AI agents full, programmatic access to email, contacts, calendar, and tasks on configured accounts. It is designed to run in the background as a menu bar app, requiring minimal human interaction beyond initial account setup and occasional status monitoring.

The core philosophy: **agents are first-class users of this email client**. The human UI exists only for configuration, status monitoring, and audit review. All functional operations flow through agent-facing interfaces (MCP, CLI, REST API).

### Problem Statement

AI agents increasingly need to send and receive email, manage calendars, and interact with contacts on behalf of users. Currently, giving agents access to email accounts is problematic:
- Most email clients are designed for human interaction
- Granting agents direct account credentials is risky without visibility
- No unified interface exists for agents to access email + calendar + contacts + tasks
- Polling-based approaches waste resources and introduce latency

ClawMail solves this by acting as a persistent, always-on bridge between AI agents and email account resources.

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                        ClawMail App                             │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Menu Bar │  │ Settings │  │  Audit   │  │   Account     │  │
│  │  Status  │  │  Window  │  │   Log    │  │   Manager     │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └───────┬───────┘  │
│       └──────────────┴─────────────┴────────────────┘          │
│                            │                                    │
│  ┌─────────────────────────┴─────────────────────────────────┐ │
│  │                    Core Engine                             │ │
│  │                                                           │ │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │ │
│  │  │  Email  │ │ Calendar │ │ Contacts │ │    Tasks     │ │ │
│  │  │ Manager │ │  Manager │ │  Manager │ │   Manager    │ │ │
│  │  └────┬────┘ └────┬─────┘ └────┬─────┘ └──────┬───────┘ │ │
│  │       │           │            │               │          │ │
│  │  ┌────┴───────────┴────────────┴───────────────┴───────┐ │ │
│  │  │              Protocol Layer                          │ │ │
│  │  │  IMAP/SMTP │ CalDAV │ CardDAV │ OAuth2              │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │           Local Metadata Index (SQLite)              │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  │                                                           │ │
│  │  ┌─────────────────────────────────────────────────────┐ │ │
│  │  │        Guardrails & Audit Engine                     │ │ │
│  │  └─────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────┘ │
│                            │                                    │
│  ┌─────────────────────────┴─────────────────────────────────┐ │
│  │                  Agent Interface Layer                     │ │
│  │                                                           │ │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────────────┐    │ │
│  │  │   MCP    │    │   CLI    │    │    REST API      │    │ │
│  │  │ (stdio)  │    │          │    │  (localhost:port) │    │ │
│  │  └──────────┘    └──────────┘    └──────────────────┘    │ │
│  └───────────────────────────────────────────────────────────┘ │
│                            │                                    │
└────────────────────────────┼────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │      Mail Servers           │
              │  IMAP/SMTP, CalDAV, CardDAV │
              │  OAuth2 (Gmail, Outlook)    │
              └─────────────────────────────┘
```

### Concurrency Model

**Single agent connection at a time.** If an agent is connected via MCP and another attempts to connect, the second connection is rejected with a clear error message. The CLI and REST API share this same lock — all three interfaces compete for the single agent slot. This avoids race conditions and conflicting operations on the mailbox.

The human UI (menu bar, settings window) is always accessible regardless of agent connection state.

---

## Agent Interfaces

ClawMail exposes three agent-facing interfaces. All three provide access to the same operations and share the same underlying engine. An agent uses whichever interface suits its capabilities.

### 1. MCP Server (Primary — stdio transport)

The MCP (Model Context Protocol) server is the primary agent interface. It uses **stdio transport**, meaning the ClawMail app spawns a child process that communicates via stdin/stdout.

**Configuration for Claude Code** (in `.mcp.json` or MCP settings):
```json
{
  "mcpServers": {
    "clawmail": {
      "command": "/usr/local/bin/clawmail",
      "args": ["mcp"]
    }
  }
}
```

**Key advantage**: MCP supports **server-initiated notifications**. When new email arrives (detected via IMAP IDLE), ClawMail pushes a notification to the connected agent without polling.

**MCP Resources** (read-only data the agent can access):
- `clawmail://accounts` — list of configured accounts
- `clawmail://accounts/{id}/status` — connection status, mailbox stats
- `clawmail://accounts/{id}/folders` — folder/label listing with unread counts

**MCP Tools** (actions the agent can perform): See [Agent Operations](#agent-operations) below.

**MCP Notifications** (pushed to agent):
- `clawmail/newMail` — new email received (includes account ID, folder, message metadata)
- `clawmail/connectionStatus` — account connection state changed
- `clawmail/error` — error occurred (auth failure, connection lost, etc.)

### 2. CLI

The `clawmail` CLI provides the same operations as the MCP server but via shell commands. Agents that interact via Bash/shell (like Claude Code using the Bash tool) can use this directly.

**Command structure**: `clawmail <resource> <action> [flags]`

**Output format**: JSON by default. Supports `--format=json` (default), `--format=text` (human-readable), `--format=csv` (for tabular data).

**Examples**:
```bash
# List accounts
clawmail accounts list

# Read the 10 most recent emails in inbox
clawmail email list --account=work --folder=INBOX --limit=10

# Read a specific email (returns structured + cleaned content)
clawmail email read --account=work --id=<message-id>

# Send an email
clawmail email send --account=work \
  --to="alice@example.com" \
  --subject="Meeting notes" \
  --body="Here are the notes from today's meeting..." \
  --attach="/path/to/notes.pdf"

# Search emails
clawmail email search --account=work --query="from:bob subject:invoice"

# List calendar events
clawmail calendar list --account=work --from=2025-01-01 --to=2025-01-31

# Create a calendar event
clawmail calendar create --account=work \
  --title="Team standup" \
  --start="2025-01-15T09:00:00" \
  --end="2025-01-15T09:30:00" \
  --attendees="alice@example.com,bob@example.com"

# List contacts
clawmail contacts list --account=personal --query="Alice"

# Create a task
clawmail tasks create --account=work \
  --title="Review Q4 report" \
  --due="2025-01-20" \
  --priority=high

# View audit log
clawmail audit list --limit=50

# Check app status
clawmail status
```

**Account targeting**: When multiple accounts are configured, the `--account` flag specifies which account to use. If omitted, the CLI returns an error listing available accounts (no implicit default to avoid accidental misuse).

### 3. REST API (localhost)

A local HTTP server bound to `127.0.0.1` on a configurable port (default: `24601`).

**Authentication**: API key generated during initial setup. Passed via `Authorization: Bearer <api-key>` header. The API key is stored in macOS Keychain and can be regenerated from the Settings window.

**Base URL**: `http://127.0.0.1:24601/api/v1`

**Endpoints mirror the CLI command structure**:
```
GET    /accounts
GET    /accounts/{id}/status

GET    /email?account={id}&folder=INBOX&limit=10
GET    /email/{message-id}?account={id}
POST   /email/send
POST   /email/reply
POST   /email/forward
DELETE /email/{message-id}?account={id}
PATCH  /email/{message-id}?account={id}   (move, flag, mark read/unread)
GET    /email/search?account={id}&q=...

GET    /calendar/events?account={id}&from=...&to=...
POST   /calendar/events
PUT    /calendar/events/{id}
DELETE /calendar/events/{id}

GET    /contacts?account={id}&q=...
POST   /contacts
PUT    /contacts/{id}
DELETE /contacts/{id}

GET    /tasks?account={id}
POST   /tasks
PUT    /tasks/{id}
DELETE /tasks/{id}

GET    /audit?limit=50&offset=0

GET    /status
```

**Webhook support**: The REST API supports an optional webhook URL (configured in settings). When new email arrives, ClawMail POSTs a notification to the webhook URL. This is the REST equivalent of MCP's push notifications.

---

## Agent Operations

These operations are available through all three interfaces (MCP, CLI, REST). The descriptions below are interface-agnostic.

### Email Operations

#### List Messages
- **Input**: account ID, folder (default: INBOX), limit (default: 20), offset (default: 0), sort (default: date descending)
- **Output**: Array of message summaries (id, from, to, cc, subject, date, flags, size, has_attachments)

#### Read Message
- **Input**: account ID, message ID
- **Output**: Full structured message:
  ```json
  {
    "id": "<message-id>",
    "account": "work",
    "folder": "INBOX",
    "from": {"name": "Alice Smith", "email": "alice@example.com"},
    "to": [{"name": "Agent", "email": "agent@example.com"}],
    "cc": [],
    "bcc": [],
    "subject": "Meeting notes",
    "date": "2025-01-15T14:30:00Z",
    "flags": ["seen"],
    "body_plain": "Cleaned plain text body (signatures and quoted text stripped)",
    "body_plain_raw": "Original plain text body (unmodified)",
    "body_html": "Original HTML body",
    "attachments": [
      {
        "filename": "notes.pdf",
        "mime_type": "application/pdf",
        "size": 245000
      }
    ],
    "headers": {
      "message-id": "<abc123@example.com>",
      "in-reply-to": "<def456@example.com>",
      "references": "<def456@example.com>"
    }
  }
  ```
- **Cleaning behavior**: `body_plain` strips email signatures (detected via `-- ` delimiter and common patterns), removes quoted reply blocks (lines starting with `>`), and collapses excessive whitespace. `body_plain_raw` provides the unmodified original. The agent always gets both.

#### Send Message
- **Input**: account ID, to (array), cc (array, optional), bcc (array, optional), subject, body (plain text), body_html (optional), attachments (array of file paths, optional), in_reply_to (message ID, optional for setting reply headers)
- **Output**: Sent message ID, success/failure status
- **Behavior**: If `body_html` is not provided, the plain text body is sent as-is (no auto-conversion to HTML). Attachments are read from the provided filesystem paths at send time.

#### Reply to Message
- **Input**: account ID, original message ID, body, body_html (optional), attachments (optional), reply_all (boolean, default: false)
- **Output**: Sent message ID
- **Behavior**: Automatically sets In-Reply-To and References headers. Populates To/CC from the original message based on reply_all flag.

#### Forward Message
- **Input**: account ID, original message ID, to (array), body (optional prepended text), attachments (optional additional attachments)
- **Output**: Sent message ID
- **Behavior**: Includes original message body and all original attachments.

#### Move Message
- **Input**: account ID, message ID, destination folder
- **Output**: success/failure

#### Delete Message
- **Input**: account ID, message ID, permanent (boolean, default: false)
- **Output**: success/failure
- **Behavior**: If permanent=false, moves to Trash. If permanent=true, permanently deletes (EXPUNGE).

#### Update Flags
- **Input**: account ID, message ID, flags to add, flags to remove
- **Supported flags**: seen, flagged, answered, draft
- **Output**: updated flag list

#### Search Messages
- **Input**: account ID, query string, folder (optional, searches all if omitted), limit, offset
- **Query syntax**: Supports field-specific search:
  - `from:alice@example.com` — sender
  - `to:bob@example.com` — recipient
  - `subject:invoice` — subject contains
  - `body:quarterly report` — body contains
  - `has:attachment` — has attachments
  - `is:unread` / `is:read` / `is:flagged` — flag filters
  - `before:2025-01-15` / `after:2025-01-01` — date ranges
  - `in:INBOX` — folder filter
  - Free text (no prefix) searches across subject and body
  - Terms can be combined: `from:alice subject:invoice after:2025-01-01`
- **Output**: Array of message summaries (same format as List Messages)
- **Implementation**: Searches the local metadata index first. Falls back to IMAP SEARCH for body content if not locally indexed.

#### List Folders
- **Input**: account ID
- **Output**: Array of folders with name, path, unread count, total count, and any subfolders (hierarchical)

#### Create Folder
- **Input**: account ID, folder name, parent folder (optional)
- **Output**: created folder info

#### Delete Folder
- **Input**: account ID, folder path
- **Output**: success/failure

#### Download Attachment
- **Input**: account ID, message ID, attachment filename (or index), destination path
- **Output**: local file path where attachment was saved, file size
- **Behavior**: Downloads the attachment from the server and writes it to the specified destination path. Creates parent directories if needed.

### Calendar Operations

All calendar operations use CalDAV.

#### List Events
- **Input**: account ID, from (datetime), to (datetime), calendar name (optional — lists from all calendars if omitted)
- **Output**: Array of events:
  ```json
  {
    "id": "event-uid",
    "calendar": "Work",
    "title": "Team standup",
    "start": "2025-01-15T09:00:00Z",
    "end": "2025-01-15T09:30:00Z",
    "location": "Room 3B",
    "description": "Daily sync",
    "attendees": [
      {"name": "Alice", "email": "alice@example.com", "status": "accepted"}
    ],
    "recurrence": null,
    "reminders": [{"minutes_before": 10}],
    "all_day": false
  }
  ```

#### Create Event
- **Input**: account ID, calendar name, title, start, end, location (optional), description (optional), attendees (optional array of emails), recurrence (optional RRULE string), reminders (optional), all_day (boolean, default: false)
- **Output**: created event with ID

#### Update Event
- **Input**: account ID, event ID, any fields to update (partial update)
- **Output**: updated event

#### Delete Event
- **Input**: account ID, event ID
- **Output**: success/failure

#### List Calendars
- **Input**: account ID
- **Output**: Array of calendars with name, color, and default flag

### Contacts Operations

All contacts operations use CardDAV.

#### List/Search Contacts
- **Input**: account ID, query (optional — searches name and email), address book (optional), limit, offset
- **Output**: Array of contacts:
  ```json
  {
    "id": "contact-uid",
    "address_book": "Contacts",
    "display_name": "Alice Smith",
    "first_name": "Alice",
    "last_name": "Smith",
    "emails": [
      {"type": "work", "address": "alice@company.com"},
      {"type": "personal", "address": "alice@gmail.com"}
    ],
    "phones": [
      {"type": "mobile", "number": "+1-555-0123"}
    ],
    "organization": "Acme Corp",
    "title": "Engineering Lead",
    "notes": "Met at conference 2024"
  }
  ```

#### Create Contact
- **Input**: account ID, address book, contact fields (see structure above)
- **Output**: created contact with ID

#### Update Contact
- **Input**: account ID, contact ID, fields to update (partial update)
- **Output**: updated contact

#### Delete Contact
- **Input**: account ID, contact ID
- **Output**: success/failure

#### List Address Books
- **Input**: account ID
- **Output**: Array of address book names

### Tasks Operations

Tasks use CalDAV VTODO.

#### List Tasks
- **Input**: account ID, task list (optional), include_completed (boolean, default: false), sort (default: due date ascending)
- **Output**: Array of tasks:
  ```json
  {
    "id": "task-uid",
    "task_list": "Work",
    "title": "Review Q4 report",
    "description": "Detailed review of financials",
    "due": "2025-01-20T17:00:00Z",
    "priority": "high",
    "status": "needs-action",
    "percent_complete": 0,
    "created": "2025-01-10T08:00:00Z",
    "modified": "2025-01-10T08:00:00Z"
  }
  ```

#### Create Task
- **Input**: account ID, task list, title, description (optional), due (optional), priority (optional: low/medium/high), status (optional, default: needs-action)
- **Output**: created task with ID

#### Update Task
- **Input**: account ID, task ID, fields to update (partial update)
- **Output**: updated task
- **Common use**: marking complete by setting status to "completed"

#### Delete Task
- **Input**: account ID, task ID
- **Output**: success/failure

#### List Task Lists
- **Input**: account ID
- **Output**: Array of task list names

---

## Email Protocols & Authentication

### IMAP/SMTP (Baseline)

All email accounts connect via IMAP (for receiving/reading) and SMTP (for sending). This provides universal compatibility.

**Connection requirements**:
- IMAP: SSL/TLS required (port 993) or STARTTLS (port 143)
- SMTP: SSL/TLS required (port 465) or STARTTLS (port 587)
- No support for unencrypted connections

**Authentication methods**:
- Username + password (stored in macOS Keychain)
- App-specific passwords (for providers that support them)
- OAuth2 (for Gmail and Outlook — see below)

**IMAP IDLE**: ClawMail maintains a persistent IMAP IDLE connection on the INBOX (and optionally other configured folders) to receive real-time notifications of new mail. When IDLE notifies of new messages, ClawMail fetches the message metadata, updates the local index, and pushes a notification to any connected agent via MCP.

### OAuth2 (Gmail & Outlook)

For Google Workspace / Gmail and Microsoft 365 / Outlook accounts, ClawMail supports OAuth2 authentication. This is increasingly required as these providers phase out basic authentication.

**OAuth2 Flow**:
1. User clicks "Add Account" → selects Google or Microsoft
2. ClawMail opens the system browser to the provider's OAuth2 consent page
3. User grants permission
4. Provider redirects to a local callback URL (`http://127.0.0.1:<port>/oauth/callback`)
5. ClawMail exchanges the authorization code for access + refresh tokens
6. Tokens are stored in macOS Keychain
7. ClawMail automatically refreshes access tokens before expiry

**Required OAuth2 Scopes**:
- Gmail: `https://mail.google.com/` (full IMAP/SMTP access via XOAUTH2), `https://www.googleapis.com/auth/calendar`, `https://www.googleapis.com/auth/contacts`
- Microsoft: `offline_access`, `IMAP.AccessAsUser.All`, `SMTP.Send`, `Calendars.ReadWrite`, `Contacts.ReadWrite`, `Tasks.ReadWrite`

**Note on OAuth2 App Registration**: ClawMail will need to be registered as an OAuth2 application with both Google and Microsoft. The spec assumes the developer will register the app and include client IDs in the build. For self-hosted/development builds, users can provide their own OAuth2 client ID and secret in settings.

### CalDAV / CardDAV

Calendar, contacts, and tasks connect via CalDAV and CardDAV respectively. These are configured per-account.

**Auto-discovery**: ClawMail attempts to auto-discover CalDAV/CardDAV endpoints using:
1. DNS SRV records (`_caldavs._tcp`, `_carddavs._tcp`)
2. Well-known URLs (`/.well-known/caldav`, `/.well-known/carddav`)
3. Manual URL entry as fallback

**Known provider endpoints** (built-in):
- Google: `https://www.googleapis.com/caldav/v2/`, `https://www.googleapis.com/.well-known/carddav`
- iCloud: `https://caldav.icloud.com/`, `https://contacts.icloud.com/`
- Fastmail: `https://caldav.fastmail.com/`, `https://carddav.fastmail.com/`
- Microsoft 365: CalDAV/CardDAV support varies; for Microsoft accounts, the app should note limitations and recommend using Google or other providers for calendar/contacts if CalDAV is unavailable

**Authentication**: Uses the same credentials as the email account (password or OAuth2 token).

---

## Account Configuration

### Account Setup Flow

1. User opens Settings window → Accounts tab → "Add Account"
2. **Provider selection**: User selects from:
   - Google (Gmail / Google Workspace) → OAuth2 flow
   - Microsoft (Outlook / Microsoft 365) → OAuth2 flow
   - Other (Generic IMAP/SMTP) → manual configuration
3. **For OAuth2 providers**: Browser-based consent flow (see OAuth2 section above)
4. **For generic IMAP/SMTP**:
   - Email address
   - IMAP server hostname + port
   - SMTP server hostname + port
   - Username (default: email address)
   - Password (stored in macOS Keychain)
   - CalDAV URL (optional, with auto-discovery attempt)
   - CardDAV URL (optional, with auto-discovery attempt)
5. **Connection test**: ClawMail tests the connection before saving
6. **Account label**: User provides a short label (e.g., "work", "personal") used as the account identifier in agent commands

### Account Data Model

```swift
struct Account: Identifiable, Codable {
    let id: UUID
    var label: String                    // e.g., "work" — used in CLI/API
    var emailAddress: String
    var displayName: String              // Used as sender name

    // Authentication
    var authMethod: AuthMethod           // .password or .oauth2(provider)
    // Credentials stored in Keychain, referenced by account ID

    // IMAP
    var imapHost: String
    var imapPort: Int                    // default: 993
    var imapSecurity: ConnectionSecurity // .ssl, .starttls

    // SMTP
    var smtpHost: String
    var smtpPort: Int                    // default: 465 or 587
    var smtpSecurity: ConnectionSecurity

    // CalDAV (optional)
    var caldavURL: URL?

    // CardDAV (optional)
    var carddavURL: URL?

    // State
    var isEnabled: Bool
    var lastSyncDate: Date?
    var connectionStatus: ConnectionStatus
}
```

---

## Local Metadata Index

ClawMail maintains a **SQLite database** for fast local search and metadata caching. This is stored at `~/Library/Application Support/ClawMail/metadata.sqlite`.

### What is Indexed

- **Message metadata**: message ID, account, folder, from, to, cc, subject, date, flags, size, has_attachments
- **Full-text search index**: Subject and (when available from IMAP FETCH BODY.PEEK) plain text body content, using SQLite FTS5
- **Folder structure**: folder names, hierarchy, UIDVALIDITY for sync tracking
- **Sync state**: IMAP UIDs, HIGHESTMODSEQ for efficient delta sync

### What is NOT Stored Locally

- Full message bodies (fetched on-demand from IMAP server)
- Attachments (downloaded on-demand)
- HTML bodies (fetched on-demand)
- Calendar events, contacts, tasks (queried from CalDAV/CardDAV on-demand; these protocols are lightweight enough that local caching is unnecessary)

### Sync Strategy

1. **Initial sync**: On account setup, fetch metadata for the last 30 days of messages (configurable). Build the FTS index.
2. **Incremental sync**: Use IMAP CONDSTORE/QRESYNC (if supported by server) for efficient delta sync. Fall back to UID-based comparison.
3. **Real-time updates**: IMAP IDLE on INBOX (and optionally other folders). When IDLE signals new messages, immediately fetch their metadata and update the index.
4. **Periodic full sync**: Every 15 minutes (configurable), do a full metadata reconciliation to catch any missed changes.

---

## Guardrails & Audit System

### Configurable Guardrails

All guardrails are **off by default** and can be enabled/configured in the Settings window. They apply to agent actions only (not direct user actions from the Settings UI).

#### Send Rate Limiting
- **Setting**: Maximum emails per minute / per hour / per day
- **Default**: Off (unlimited)
- **Behavior**: When limit is hit, the send operation returns an error with the rate limit details and when the agent can retry

#### Domain Allowlist
- **Setting**: List of allowed recipient domains
- **Default**: Off (all domains allowed)
- **Behavior**: When enabled, the agent can only send to email addresses at listed domains. Attempts to send to unlisted domains return an error.

#### Domain Blocklist
- **Setting**: List of blocked recipient domains
- **Default**: Off (no domains blocked)
- **Behavior**: Blocks sends to the listed domains. If both allowlist and blocklist are configured, the allowlist takes precedence (only allowed domains are permitted).

#### First-Time Recipient Approval
- **Setting**: On/Off toggle
- **Default**: Off
- **Behavior**: When enabled, the first time an agent sends to a new email address, the send is held and the human is notified (via macOS notification). The human can approve or reject from the Settings window. Subsequent sends to approved recipients go through immediately.
- **Storage**: Approved recipients list persisted in the local database.

### Audit Log

All agent operations are logged, regardless of guardrail settings. The audit log is always active and cannot be disabled.

**Log entry structure**:
```json
{
  "timestamp": "2025-01-15T14:30:00.123Z",
  "interface": "mcp",
  "operation": "email.send",
  "account": "work",
  "parameters": {
    "to": ["alice@example.com"],
    "subject": "Meeting notes"
  },
  "result": "success",
  "details": {
    "message_id": "<abc123@example.com>"
  }
}
```

**Log storage**: SQLite table in the same database as the metadata index. Logs are retained for 90 days by default (configurable).

**Log access**:
- Human: Browsable in the Settings window under "Activity Log" tab, with filtering and search
- Agent: Via `clawmail audit list` (CLI), `/api/v1/audit` (REST), or MCP tool `audit_list`

**What is logged**:
- All email operations (send, delete, move, flag changes)
- All calendar operations (create, update, delete events)
- All contacts operations (create, update, delete)
- All task operations (create, update, delete)
- Search queries
- Authentication events (login, token refresh, failures)
- Guardrail triggers (rate limit hit, blocked domain, held message)

**What is NOT logged**:
- Read-only operations on individual messages (to avoid excessive log volume). List and search operations ARE logged.

---

## macOS App Design

### Menu Bar

**Icon**: A stylized envelope/claw icon in the menu bar. The icon changes appearance to indicate status:
- **Normal** (outline): All accounts connected, no issues
- **Active** (filled): An agent is currently connected
- **Warning** (with dot): One or more accounts have connection issues
- **Error** (red): Authentication failure or critical error

**Dropdown menu** (click on menu bar icon):
```
ClawMail
─────────────────────
✓ Connected: work (agent active)
✓ Connected: personal
─────────────────────
Last activity: Sent email (2 min ago)
Unread: 12 work, 3 personal
─────────────────────
Settings...          ⌘,
Activity Log...
─────────────────────
Quit ClawMail        ⌘Q
```

### Settings Window

A proper macOS window opened from the menu bar dropdown. Organized with a sidebar or tab bar:

#### Accounts Tab
- List of configured accounts with status indicators
- Add / Edit / Remove account buttons
- Per-account settings:
  - Account label, email, display name
  - Server configuration (IMAP/SMTP/CalDAV/CardDAV)
  - Enable/disable toggle
  - Test connection button

#### Guardrails Tab
- Send rate limits (toggle + configure)
- Domain allowlist (toggle + list editor)
- Domain blocklist (toggle + list editor)
- First-time recipient approval (toggle)
- View/manage approved recipients list

#### API Tab
- REST API port configuration
- API key display (masked) with copy and regenerate buttons
- MCP server status
- CLI path display
- Webhook URL configuration (for REST API push notifications)

#### Activity Log Tab
- Scrollable, filterable list of audit log entries
- Filters: by account, by operation type, by date range, by interface
- Search within log entries
- Export log (JSON or CSV)

#### General Tab
- Launch at login toggle
- Initial sync period (default: 30 days)
- Periodic sync interval (default: 15 minutes)
- Audit log retention (default: 90 days)
- IMAP IDLE folders (INBOX by default, configurable)

### Background Operation

ClawMail registers as a **macOS Launch Agent** to start at login. It runs as a background process with no Dock icon (LSUIElement = true in Info.plist), showing only the menu bar icon.

**Launch Agent plist** (installed at `~/Library/LaunchAgents/com.clawmail.agent.plist`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clawmail.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/clawmail</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

---

## Tech Stack

### Core
- **Language**: Swift 6 (with strict concurrency checking)
- **UI Framework**: SwiftUI (macOS 14+ / Sonoma minimum deployment target)
- **Concurrency**: Swift structured concurrency (async/await, actors)
- **Build System**: Swift Package Manager

### Dependencies (Swift Packages)

- **SwiftNIO** — High-performance networking foundation for IMAP/SMTP connections
- **swift-nio-ssl** — TLS support for SwiftNIO
- **SwiftNIO IMAP** (or equivalent) — IMAP protocol implementation. If a mature Swift IMAP library is unavailable, implement IMAP client using SwiftNIO directly with the IMAP4rev1 RFC.
- **SwiftSMTP** (or equivalent) — SMTP client for sending email. Evaluate available packages; implement directly on SwiftNIO if needed.
- **SQLite.swift** or **GRDB.swift** — SQLite database access for metadata index and audit log
- **SwiftArgumentParser** — CLI argument parsing for the `clawmail` command
- **KeychainAccess** (or native Security framework) — macOS Keychain integration for credential storage
- **MCP Swift SDK** — If available, use the official or community MCP SDK for Swift. If none exists, implement the MCP stdio protocol directly (it's JSON-RPC 2.0 over stdin/stdout).
- **Vapor** (or **Hummingbird**) — Lightweight HTTP server for the REST API. Hummingbird is lighter weight and may be preferable since we only need a simple localhost API.
- **SwiftSoup** — HTML parsing for email body cleaning

### Project Structure

```
ClawMail/
├── Package.swift
├── Sources/
│   ├── ClawMailApp/              # macOS app target
│   │   ├── ClawMailApp.swift     # App entry point (@main)
│   │   ├── MenuBar/
│   │   │   ├── MenuBarManager.swift
│   │   │   └── StatusMenu.swift
│   │   ├── Settings/
│   │   │   ├── SettingsWindow.swift
│   │   │   ├── AccountsTab.swift
│   │   │   ├── GuardrailsTab.swift
│   │   │   ├── APITab.swift
│   │   │   ├── ActivityLogTab.swift
│   │   │   └── GeneralTab.swift
│   │   ├── Account/
│   │   │   ├── AccountSetupView.swift
│   │   │   ├── OAuthFlowView.swift
│   │   │   └── ConnectionTestView.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       └── Info.plist
│   │
│   ├── ClawMailCore/              # Core engine (shared library)
│   │   ├── Models/
│   │   │   ├── Account.swift
│   │   │   ├── Email.swift
│   │   │   ├── CalendarEvent.swift
│   │   │   ├── Contact.swift
│   │   │   ├── Task.swift
│   │   │   └── AuditEntry.swift
│   │   ├── Email/
│   │   │   ├── IMAPClient.swift
│   │   │   ├── SMTPClient.swift
│   │   │   ├── EmailManager.swift
│   │   │   ├── EmailCleaner.swift   # Signature/quote stripping
│   │   │   └── IMAPIdleMonitor.swift
│   │   ├── Calendar/
│   │   │   ├── CalDAVClient.swift
│   │   │   └── CalendarManager.swift
│   │   ├── Contacts/
│   │   │   ├── CardDAVClient.swift
│   │   │   └── ContactsManager.swift
│   │   ├── Tasks/
│   │   │   ├── TaskManager.swift
│   │   │   └── VTODOParser.swift
│   │   ├── Auth/
│   │   │   ├── OAuth2Manager.swift
│   │   │   ├── KeychainManager.swift
│   │   │   └── CredentialStore.swift
│   │   ├── Storage/
│   │   │   ├── DatabaseManager.swift
│   │   │   ├── MetadataIndex.swift
│   │   │   └── AuditLog.swift
│   │   ├── Sync/
│   │   │   ├── SyncEngine.swift
│   │   │   └── SyncScheduler.swift
│   │   ├── Guardrails/
│   │   │   ├── GuardrailEngine.swift
│   │   │   ├── RateLimiter.swift
│   │   │   └── DomainFilter.swift
│   │   └── Search/
│   │       └── SearchEngine.swift
│   │
│   ├── ClawMailCLI/               # CLI target
│   │   ├── CLI.swift              # Entry point
│   │   ├── Commands/
│   │   │   ├── EmailCommands.swift
│   │   │   ├── CalendarCommands.swift
│   │   │   ├── ContactsCommands.swift
│   │   │   ├── TasksCommands.swift
│   │   │   ├── AccountCommands.swift
│   │   │   ├── AuditCommands.swift
│   │   │   └── StatusCommand.swift
│   │   └── Output/
│   │       └── Formatters.swift   # JSON, text, CSV output
│   │
│   ├── ClawMailMCP/               # MCP server target
│   │   ├── MCPServer.swift
│   │   ├── Tools/
│   │   │   ├── EmailTools.swift
│   │   │   ├── CalendarTools.swift
│   │   │   ├── ContactsTools.swift
│   │   │   └── TasksTools.swift
│   │   ├── Resources/
│   │   │   └── AccountResources.swift
│   │   └── Notifications/
│   │       └── MailNotifier.swift
│   │
│   └── ClawMailAPI/               # REST API target
│       ├── APIServer.swift
│       ├── Routes/
│       │   ├── EmailRoutes.swift
│       │   ├── CalendarRoutes.swift
│       │   ├── ContactsRoutes.swift
│       │   ├── TasksRoutes.swift
│       │   ├── AuditRoutes.swift
│       │   └── StatusRoutes.swift
│       ├── Middleware/
│       │   └── AuthMiddleware.swift  # API key validation
│       └── Webhook/
│           └── WebhookManager.swift
│
├── Tests/
│   ├── ClawMailCoreTests/
│   ├── ClawMailCLITests/
│   ├── ClawMailMCPTests/
│   └── ClawMailAPITests/
│
└── Resources/
    └── com.clawmail.agent.plist    # Launch agent template
```

### Build Targets

The `Package.swift` defines four targets:

1. **ClawMailCore** — Library target with all business logic, protocol clients, and data management. Shared by all other targets.
2. **ClawMailApp** — Executable target for the macOS menu bar app. Links ClawMailCore and embeds the REST API server, MCP server launcher, and SwiftUI interface.
3. **ClawMailCLI** — Executable target for the `clawmail` CLI. Links ClawMailCore. Communicates with the running ClawMailApp daemon via a local Unix domain socket (for operations that need the persistent IMAP connection) or connects directly to the IMAP server for stateless operations.
4. **ClawMailMCP** — Executable target for the MCP stdio server. Launched by the ClawMailApp when an MCP client connects. Communicates with the daemon via the same Unix domain socket.

### Inter-Process Communication

The ClawMailApp daemon is the central process that maintains IMAP connections, the metadata index, and the REST API server. The CLI and MCP processes are separate executables that communicate with the daemon:

- **Unix domain socket** at `~/Library/Application Support/ClawMail/clawmail.sock`
- **Protocol**: JSON-RPC 2.0 over the socket (same as MCP uses, keeping things consistent)
- The daemon exposes the same operation set internally as it does via REST/MCP/CLI
- If the daemon is not running, the CLI should attempt to launch it, or return an error instructing the user to start ClawMail

---

## Data Storage

All persistent data is stored under `~/Library/Application Support/ClawMail/`:

```
~/Library/Application Support/ClawMail/
├── metadata.sqlite          # Message metadata index + FTS + audit log
├── clawmail.sock           # Unix domain socket for IPC
├── config.json             # App configuration (non-secret settings)
└── oauth/                  # OAuth2 state (if needed beyond Keychain)
```

**Credentials** (passwords, OAuth2 tokens, API key) are stored in **macOS Keychain** under the service name `com.clawmail`. Never stored in plain text files.

**config.json** stores non-sensitive configuration:
```json
{
  "accounts": [...],          // Account configs (without credentials)
  "restApiPort": 24601,
  "guardrails": {
    "sendRateLimit": null,
    "domainAllowlist": null,
    "domainBlocklist": null,
    "firstTimeRecipientApproval": false
  },
  "syncIntervalMinutes": 15,
  "initialSyncDays": 30,
  "auditRetentionDays": 90,
  "idleFolders": ["INBOX"],
  "launchAtLogin": true,
  "webhookURL": null
}
```

---

## Error Handling

All agent-facing interfaces return structured errors:

```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Send rate limit exceeded. Maximum 10 emails per hour. Try again in 23 minutes.",
    "details": {
      "limit": 10,
      "period": "hour",
      "retry_after_seconds": 1380
    }
  }
}
```

**Error codes**:
- `ACCOUNT_NOT_FOUND` — specified account label doesn't exist
- `ACCOUNT_DISCONNECTED` — account exists but is not connected to the server
- `AUTH_FAILED` — authentication failure (credentials expired, token revoked)
- `MESSAGE_NOT_FOUND` — specified message ID doesn't exist
- `FOLDER_NOT_FOUND` — specified folder doesn't exist
- `RATE_LIMIT_EXCEEDED` — guardrail: send rate limit hit
- `DOMAIN_BLOCKED` — guardrail: recipient domain not allowed
- `RECIPIENT_PENDING_APPROVAL` — guardrail: first-time recipient, awaiting human approval
- `AGENT_ALREADY_CONNECTED` — another agent session is active
- `CONNECTION_ERROR` — network error communicating with mail server
- `INVALID_PARAMETER` — malformed or missing required parameter
- `SERVER_ERROR` — unexpected internal error
- `CALENDAR_NOT_AVAILABLE` — CalDAV not configured for this account
- `CONTACTS_NOT_AVAILABLE` — CardDAV not configured for this account

---

## Installation & First Run

### Installation via Homebrew

```bash
brew install --cask clawmail
```

This installs:
- `/Applications/ClawMail.app` — the menu bar application
- `/usr/local/bin/clawmail` — symlink to the CLI inside the app bundle

### First Run

1. User launches ClawMail (or it auto-launches after install)
2. Menu bar icon appears
3. Since no accounts are configured, the Settings window opens automatically to the Accounts tab
4. User adds their first account (OAuth2 or manual IMAP/SMTP)
5. ClawMail tests the connection and performs initial sync
6. Menu bar icon transitions to "connected" state
7. REST API starts on configured port
8. API key is generated and displayed (with copy button)
9. App registers as a Launch Agent for auto-start at login
10. ClawMail is ready for agent connections

### Configuring Claude Code to Use ClawMail

After installation, add to the project or global `.mcp.json`:
```json
{
  "mcpServers": {
    "clawmail": {
      "command": "/usr/local/bin/clawmail",
      "args": ["mcp"]
    }
  }
}
```

The agent can then use ClawMail tools directly in Claude Code sessions.

---

## Security Considerations

- **All credentials in Keychain**: No plain text passwords or tokens on disk
- **TLS required**: No unencrypted IMAP/SMTP/CalDAV/CardDAV connections
- **REST API localhost only**: Bound to `127.0.0.1`, not accessible from the network
- **API key authentication**: Prevents unauthorized local process access to the REST API
- **OAuth2 tokens**: Stored in Keychain, automatically refreshed, revocable
- **Audit trail**: All agent actions logged (cannot be disabled), providing accountability
- **No remote access**: The app is designed for local agent use only. Remote agents should use SSH tunneling or similar if needed.

---

## Minimum System Requirements

- **macOS**: 14.0 (Sonoma) or later
- **Disk**: ~50MB for the application, variable for metadata index
- **Network**: Active internet connection for mail server communication
- **Memory**: ~50MB typical background usage

---

## Future Considerations (Not in Initial Scope)

These features are explicitly deferred and should NOT be implemented in the initial version:

- **Multi-agent support**: Multiple simultaneous agent connections with workspace isolation
- **Email threading/conversation view**: Grouping messages by thread
- **Email templates**: Predefined email templates agents can use
- **Rich text composition**: HTML email composition with formatting
- **S/MIME or PGP**: Email encryption/signing
- **Email rules/filters**: Server-side or local email rules
- **Push notifications to remote agents**: HTTP-based MCP transport for remote agent connections
- **Draft management**: Agent-side drafts (agents handle this locally)
- **Cross-platform**: Windows/Linux support
- **Auto-responder**: Automated email responses based on rules
- **Provider-specific APIs**: Native Gmail API / Microsoft Graph for enhanced features beyond what IMAP/CalDAV/CardDAV provide
