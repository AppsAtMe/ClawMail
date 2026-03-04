# ClawMail

Agent-first email client for macOS. Gives AI agents full programmatic access to email, calendar, contacts, and tasks via MCP, CLI, and REST API.

## What Is This?

ClawMail runs as a macOS menu bar daemon, maintaining persistent IMAP connections to your email accounts. AI agents (like Claude) interact with your email through three interfaces — no browser automation or credential sharing required.

```
Agent Interfaces:  MCP (stdio) │ CLI │ REST API (localhost:24601)
        ↕                ↕              ↕
   ┌── IPC (Unix domain socket, JSON-RPC 2.0) ──┐
   ↓                                              ↓
AccountOrchestrator (central coordinator)
   ├── EmailManager (IMAP + SMTP)
   ├── CalendarManager (CalDAV)
   ├── ContactsManager (CardDAV)
   ├── TaskManager (CalDAV VTODO)
   ├── GuardrailEngine
   ├── AuditLog
   └── MetadataIndex (SQLite + FTS5)
```

## Features

- **Email**: Send, receive, search, organize — full IMAP/SMTP with real-time IDLE push notifications
- **Calendar**: Create, update, delete events via CalDAV
- **Contacts**: Manage address books via CardDAV
- **Tasks**: Full VTODO support via CalDAV
- **Search**: Full-text search with SQLite FTS5, field-specific queries (`from:alice subject:invoice`)
- **Guardrails**: Configurable rate limits, domain allow/blocklists, first-time recipient approval
- **Audit log**: Every agent action logged — always on, browsable in-app and via API
- **OAuth2**: Native support for Gmail and Microsoft 365

## Agent Interfaces

### MCP (Primary)

Add to your `.mcp.json`:

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

Supports server-initiated notifications for real-time new mail alerts.

### CLI

```bash
clawmail email list --account=work --folder=INBOX --limit=10
clawmail email send --account=work --to="alice@example.com" --subject="Hello" --body="Hi there"
clawmail calendar list --account=work --from=2025-01-01 --to=2025-01-31
clawmail contacts list --account=personal --query="Alice"
clawmail tasks create --account=work --title="Review report" --due="2025-01-20"
```

Output defaults to JSON. Use `--format=text` or `--format=csv` for alternatives.

### REST API

Local HTTP server at `http://127.0.0.1:24601/api/v1`. Authenticated via API key (`Authorization: Bearer <key>`).

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6 toolchain

## Building

```bash
swift build              # debug build
swift build -c release   # release build
swift test               # run tests
```

## Testing

Integration tests use Docker containers (GreenMail for IMAP/SMTP, Radicale for CalDAV/CardDAV):

```bash
docker compose up -d     # start test servers
swift test               # run tests against local servers
docker compose down      # stop test servers
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI (macOS 14+) |
| Build | Swift Package Manager |
| Database | SQLite via GRDB.swift (FTS5) |
| Networking | SwiftNIO (IMAP/SMTP), URLSession (CalDAV/CardDAV) |
| HTTP Server | Hummingbird |
| CLI | Swift Argument Parser |
| Credentials | macOS Keychain via KeychainAccess |
| HTML Parsing | SwiftSoup |

## Project Structure

Four build targets:

- **ClawMailCore** — Shared library: models, protocol clients, business logic
- **ClawMailApp** — macOS menu bar app (SwiftUI), embeds REST API + IPC server
- **ClawMailCLI** — CLI tool (`clawmail` command)
- **ClawMailMCP** — MCP stdio server

## Security

- All credentials stored in macOS Keychain
- TLS required for all server connections
- REST API bound to localhost only
- API key authentication
- Complete audit trail of all agent actions

## Documentation

- [`SPECIFICATION.md`](SPECIFICATION.md) — Complete feature specification
- [`BLUEPRINT.md`](BLUEPRINT.md) — Implementation blueprint with build phases

## License

MIT
