# ClawMail

Agent-first email client for macOS. Gives AI agents full programmatic access to email, calendar, contacts, and tasks via MCP, CLI, and REST API.

## What Is This?

ClawMail runs as a macOS menu bar daemon, maintaining persistent IMAP connections to your email accounts. AI agents (like Claude) interact with your email through three interfaces — no browser automation or credential sharing required.

```
Agent Interfaces:  MCP (stdio)  |  CLI  |  REST API (localhost:24601)
                        |            |              |
                  IPC (Unix domain socket, JSON-RPC 2.0)
                                     |
                         AccountOrchestrator
                 ______________|______________
                |      |       |      |       |
              Email  Calendar Contacts Tasks Guardrails
              (IMAP/  (CalDAV) (CardDAV) (VTODO) + Audit
              SMTP)                                 Log
```

The human UI exists only for setup and monitoring. All operations flow through the agent interfaces.

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+)
- Docker (optional, for integration tests)

## Installation

### From Source

```bash
git clone https://github.com/clawmail/ClawMail.git
cd ClawMail
make install
```

This builds a release binary, creates `ClawMail.app`, copies it to `/Applications`, and symlinks the CLI tools to `/usr/local/bin`:

| Symlink | Points to |
|---------|-----------|
| `/usr/local/bin/clawmail` | `ClawMail.app/Contents/MacOS/ClawMailCLI` |
| `/usr/local/bin/clawmail-mcp` | `ClawMail.app/Contents/MacOS/ClawMailMCP` |

### Uninstall

```bash
make uninstall
```

Removes the app, symlinks, and LaunchAgent.

## First-Run Setup

1. **Launch ClawMail** — open from `/Applications` or run `open /Applications/ClawMail.app`. It appears as a menu bar icon (no Dock icon).

2. **Add an account** — click the menu bar icon, open Settings, go to the Accounts tab, and click "+". The setup wizard walks through:
   - **Provider selection** (Gmail, Outlook, Other)
   - **Credentials** — server details and authentication
   - **Connection test** — verifies IMAP, SMTP, CalDAV, and CardDAV connectivity
   - **Label** — a short name used in CLI/API calls (e.g., `work`, `personal`)

3. **Configure guardrails** (optional) — Settings > Guardrails:
   - Send rate limits (per minute / hour / day)
   - Domain allowlist or blocklist
   - First-time recipient approval (requires human approval before sending to new addresses)

4. **Connect an agent** — see [Agent Interfaces](#agent-interfaces) below.

### Gmail Setup

Gmail requires an **App Password** — regular passwords are rejected with `5.7.8 BadCredentials`.

1. Go to [Google Account > Security > 2-Step Verification](https://myaccount.google.com/security)
2. Enable 2-Step Verification if not already on
3. Go to **App Passwords** (at the bottom of the 2-Step Verification page)
4. Generate a password for "Mail" on "Mac"
5. Use that 16-character password in ClawMail's account setup

Alternatively, use OAuth2 by configuring your Google Cloud OAuth client ID in Settings > API > OAuth Client IDs.

### Microsoft 365 / Outlook Setup

For OAuth2: configure your Azure AD application's client ID in Settings > API > OAuth Client IDs.

For App Passwords: enable via [Microsoft Account Security](https://account.microsoft.com/security) if your organization allows it.

## Agent Interfaces

### MCP (Primary)

Add to your Claude Code `.mcp.json` or MCP settings:

```json
{
  "mcpServers": {
    "clawmail": {
      "command": "/usr/local/bin/clawmail-mcp"
    }
  }
}
```

ClawMail provides 28 MCP tools across email, calendar, contacts, tasks, and administration. It also pushes server-initiated notifications for new mail, connection status changes, and errors.

Only one MCP session is allowed at a time (exclusive agent lock). CLI sessions run concurrently alongside.

### CLI

```bash
clawmail status                                          # daemon status
clawmail email list --account=work --folder=INBOX        # list messages
clawmail email send --account=work \
  --to="alice@example.com" \
  --subject="Report" \
  --body="See attached" \
  --attach="/path/to/report.pdf"                         # send with attachment
clawmail email search --account=work "from:bob invoice"  # full-text search
clawmail calendar list --account=work \
  --from=2026-01-01 --to=2026-01-31                      # list events
clawmail contacts list --account=personal --query="Alice" # search contacts
clawmail tasks create --account=work \
  --task-list=default --title="Review PR" --due=2026-03-10
clawmail recipients list                                 # approved recipients
clawmail audit list --account=work --limit=20            # audit log
```

Output defaults to JSON. Use `--format=text` for human-readable output.

**Available command groups**: `email`, `calendar`, `contacts`, `tasks`, `accounts`, `audit`, `recipients`, `status`

### REST API

Local HTTP server at `http://127.0.0.1:24601/api/v1`. Authenticated via Bearer token.

Retrieve the API key:

```bash
API_KEY=$(security find-generic-password -s "com.clawmail" -a "clawmail-api-key" -w)
```

Example requests:

```bash
# Check status (no auth required)
curl http://localhost:24601/api/v1/status

# List emails
curl -H "Authorization: Bearer $API_KEY" \
  "http://localhost:24601/api/v1/email?account=work&folder=INBOX&limit=10"

# Send email
curl -X POST -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"account":"work","to":[{"email":"alice@example.com"}],"subject":"Hello","body":"Hi there"}' \
  http://localhost:24601/api/v1/email/send

# Search
curl -H "Authorization: Bearer $API_KEY" \
  "http://localhost:24601/api/v1/email/search?account=work&q=from:bob+invoice"
```

Rate limited to 120 requests/minute.

**Endpoints**: `/email`, `/calendar`, `/contacts`, `/tasks`, `/accounts`, `/audit`, `/recipients`

## Search Syntax

Full-text search supports field-specific queries:

| Query | Description |
|-------|-------------|
| `invoice` | Free-text search across all fields |
| `from:alice` | Messages from alice |
| `to:bob@example.com` | Messages to a specific address |
| `subject:quarterly report` | Subject line search |
| `from:alice subject:invoice` | Combined filters |
| `has:attachment` | Messages with attachments |
| `from:alice budget` | Field filter + free text |

## Configuration

Config file: `~/Library/Application Support/ClawMail/config.json`

Most settings are managed through the Settings UI, but can also be edited directly:

```json
{
  "accounts": [],
  "restApiPort": 24601,
  "syncIntervalMinutes": 15,
  "initialSyncDays": 30,
  "auditRetentionDays": 90,
  "idleFolders": ["INBOX"],
  "launchAtLogin": true,
  "guardrails": {
    "sendRateLimit": { "maxPerHour": 20, "maxPerDay": 100 },
    "domainAllowlist": null,
    "domainBlocklist": ["competitor.com"],
    "firstTimeRecipientApproval": false
  },
  "webhookURL": "https://your-server.com/clawmail-webhook"
}
```

### Webhook Notifications

Set `webhookURL` in Settings > API to receive HTTP POST notifications when new mail arrives. Payload:

```json
{
  "event": "newMail",
  "account": "work",
  "folder": "INBOX",
  "messageId": "msg-123",
  "from": "alice@example.com",
  "subject": "Hello",
  "timestamp": "2026-03-05T10:30:00Z"
}
```

## Data Locations

| Item | Path |
|------|------|
| Config | `~/Library/Application Support/ClawMail/config.json` |
| Database | `~/Library/Application Support/ClawMail/metadata.sqlite` |
| IPC socket | `~/Library/Application Support/ClawMail/clawmail.sock` |
| IPC token | `~/Library/Application Support/ClawMail/ipc.token` |
| Credentials | macOS Keychain (service: `com.clawmail`) |
| LaunchAgent | `~/Library/LaunchAgents/com.clawmail.agent.plist` |
| Logs | `/tmp/clawmail.stdout.log`, `/tmp/clawmail.stderr.log` |

## Security

- **Credentials**: Stored in macOS Keychain with `.afterFirstUnlockThisDeviceOnly` — never synced to iCloud
- **TLS**: Required for all IMAP/SMTP/CalDAV/CardDAV connections
- **REST API**: Bound to localhost only, authenticated via API key, rate-limited (120 req/min)
- **IPC**: Token file with 0600 permissions, peer PID verification, socket directory chmod 0700
- **Guardrails**: Configurable send rate limits, domain allow/blocklists, first-time recipient approval
- **Audit**: Every agent write operation is logged with timestamp, action, account, and parameters
- **Input validation**: IMAP/SMTP injection prevention, FTS5 query sanitization, path traversal blocking
- **Attachment security**: Downloads restricted to `~/Downloads`, `~/Documents`, `~/Desktop`, and temp. Reads blocked from `/etc`, `.ssh`, `.gnupg`, Keychains.

## Building & Testing

```bash
# Development
swift build                  # debug build
swift build -c release       # release build
swift test                   # unit tests (no Docker needed)

# Integration tests (requires Docker)
make test-all                # start containers, run tests, stop containers

# Or manually:
docker compose up -d         # start GreenMail (IMAP/SMTP) + Radicale (CalDAV/CardDAV)
swift test                   # run all tests
docker compose down          # stop containers

# Packaging
make bundle                  # create .app bundle
make sign                    # ad-hoc code sign (local dev)
make dmg                     # create distributable DMG
make install                 # install to /Applications + symlink CLI
make uninstall               # remove everything
```

### Release Build with Signing

```bash
make dmg SIGNING_ID="Developer ID Application: Your Name (TEAMID)"
```

### Notarization

Requires a Developer ID certificate and stored credentials:

```bash
# One-time: store notarization credentials
xcrun notarytool store-credentials "notarytool-password" \
  --apple-id you@example.com \
  --team-id XXXXXXXXXX \
  --password "app-specific-password"

# Build, sign, package, and notarize
make notarize \
  SIGNING_ID="Developer ID Application: Your Name (TEAMID)" \
  TEAM_ID=XXXXXXXXXX
```

## Project Structure

```
ClawMail/
  Sources/
    ClawMailCore/       # Shared library: models, protocol clients, business logic
      Models/           #   Data models (Account, EmailSummary, CalendarEvent, etc.)
      Email/            #   IMAP client, SMTP client, EmailManager, search engine
      Calendar/         #   CalDAV client, CalendarManager
      Contacts/         #   CardDAV client, ContactsManager
      Auth/             #   OAuth2Manager, OAuthHelpers
      Storage/          #   MetadataIndex (SQLite/FTS5), CredentialStore, AuditLog
      Guardrails/       #   GuardrailEngine
      Sync/             #   SyncEngine, SyncScheduler
      IPC/              #   JSON-RPC 2.0 server/client, dispatcher
      Webhook/          #   WebhookManager
    ClawMailAppLib/      # REST API library (routes, middlewares)
    ClawMailApp/         # macOS menu bar app (SwiftUI)
    ClawMailCLI/         # CLI tool
    ClawMailMCP/         # MCP stdio server
  Tests/
    ClawMailCoreTests/          # Unit tests for core library
    ClawMailAppLibTests/        # REST API tests
    ClawMailIntegrationTests/   # Docker-dependent integration tests
  Resources/            # LaunchAgent plist template
  HomebrewFormula/      # Homebrew Cask formula
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI (macOS 14+) |
| Build | Swift Package Manager |
| Database | SQLite via GRDB.swift (FTS5 for search) |
| Networking | SwiftNIO (IMAP/SMTP), URLSession (CalDAV/CardDAV) |
| HTTP Server | Hummingbird 2.x |
| CLI | Swift Argument Parser |
| Credentials | macOS Keychain via KeychainAccess |
| HTML Parsing | SwiftSoup |

## Documentation

- [`SPECIFICATION.md`](SPECIFICATION.md) — Complete feature specification
- [`BLUEPRINT.md`](BLUEPRINT.md) — Implementation blueprint with build phases

## License

MIT
