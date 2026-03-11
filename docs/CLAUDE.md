# ClawMail

Agent-first email client for macOS. Gives AI agents full programmatic access to email, calendar, contacts, and tasks via MCP, CLI, and REST API.

## Key Documents

- `SPECIFICATION.md` — Complete feature specification (the "what")
- `BLUEPRINT.md` — Implementation blueprint with build phases (the "how")

Read both before starting any implementation work.

## Tech Stack

- **Language**: Swift 6 (strict concurrency)
- **UI**: SwiftUI (macOS 14+ / Sonoma)
- **Build**: Swift Package Manager
- **Database**: SQLite via GRDB.swift (FTS5 for search)
- **Networking**: SwiftNIO (IMAP/SMTP), URLSession (CalDAV/CardDAV)
- **HTTP Server**: Hummingbird (REST API on localhost)
- **CLI**: Swift Argument Parser
- **Credentials**: macOS Keychain via KeychainAccess

## Architecture Summary

```
Agent Interfaces:  MCP (stdio) | CLI | REST API (localhost:24601)
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

The macOS app runs as a menu bar daemon (LSUIElement). CLI and MCP are separate executables that connect to the daemon via Unix domain socket.

## Project Structure

Five build targets in Package.swift:
- `ClawMailCore` — shared library (models, protocol clients, business logic)
- `ClawMailAppLib` — REST API library (routes, middlewares, helpers)
- `ClawMailApp` — macOS menu bar app (SwiftUI, imports ClawMailAppLib)
- `ClawMailCLI` — CLI tool (`clawmail` command)
- `ClawMailMCP` — MCP stdio server

## Conventions

- Use Swift actors for all stateful components (thread safety via actor isolation)
- All agent-facing operations go through `AccountOrchestrator`
- Every write operation: guardrail check → execute → audit log
- Error types: always use `ClawMailError` enum, never leak protocol errors to agents
- JSON-RPC 2.0 for all IPC (daemon ↔ CLI/MCP)
- Models must be `Codable` and `Sendable`

## Building

```bash
swift build              # debug build
swift build -c release   # release build
swift test               # run tests
```

## Testing

Local test servers via Docker (GreenMail for IMAP/SMTP):
```bash
docker compose up -d     # start test servers
swift test               # run tests against local servers
docker compose down      # stop test servers
```

## Agent Team Build Strategy

The blueprint (BLUEPRINT.md) includes an agent team orchestration section. Key principle: 2-3 agents working on independent modules simultaneously, with clear interface contracts defined upfront. See "Agent Team Orchestration" appendix in BLUEPRINT.md.

## Data Locations

- App config: `~/Library/Application Support/ClawMail/config.json`
- Database: `~/Library/Application Support/ClawMail/metadata.sqlite`
- IPC socket: `~/Library/Application Support/ClawMail/clawmail.sock`
- IPC token: `~/Library/Application Support/ClawMail/ipc.token` (0600)
- Credentials: macOS Keychain (service: `com.clawmail`)
- API key: Keychain account `clawmail-api-key` (retrieve: `security find-generic-password -s "com.clawmail" -a "clawmail-api-key" -w`)
- LaunchAgent: `~/Library/LaunchAgents/com.clawmail.agent.plist`

## Known Limitations

- **IPC agent exclusivity**: Only one agent (MCP) session at a time. CLI sessions are concurrent and can coexist with an active agent. See `IPCSessionType` in `IPCServer.swift`.
- **Gmail requires App Passwords**: Regular passwords rejected with `5.7.8 BadCredentials`.
- **NIO error display**: Always use `String(describing: error)` not `error.localizedDescription` for NIO errors — Foundation produces generic "error N" messages.
