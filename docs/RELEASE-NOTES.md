# ClawMail Release Notes

## Version 1.0.0 — Initial Release

**Release Date:** March 2026  
**Status:** Stable

---

### 🎉 Initial Release

ClawMail 1.0.0 is our first stable release — an agent-first email client for macOS that gives AI agents programmatic access to email, calendar, contacts, and tasks.

### ✨ Key Features

**Email (IMAP/SMTP)**
- Read, send, and search email
- Full folder management
- Attachment handling
- Persistent IMAP connections

**Calendar (CalDAV)**
- List, create, and update events
- Multiple calendar support
- Recurring event handling

**Contacts (CardDAV)**
- Search and manage contacts
- Contact group support
- vCard import/export

**Tasks (VTODO)**
- Manage todo items
- Due dates and priorities
- Task list organization

**Agent Interfaces**
- **MCP** (Model Context Protocol) — For AI agents like Claude
- **CLI** — For terminal workflows
- **REST API** — For custom integrations

**Provider Support**
- Google (Gmail) — OAuth2
- Microsoft 365 / Outlook — OAuth2
- Apple / iCloud — App-specific password
- Fastmail — App password
- Other — Any IMAP/SMTP provider

**Security & Privacy**
- Local-first architecture
- Credentials stored in macOS Keychain
- No cloud processing
- No telemetry or data collection
- Guardrails for send approval and rate limiting

### 🛠️ Technical Stack

**Language & Framework**
- Swift 6 (strict concurrency)
- SwiftUI for macOS UI
- Swift Package Manager

**Networking**
- SwiftNIO for IMAP/SMTP
- URLSession for CalDAV/CardDAV
- Hummingbird 2.x for REST API

**Storage**
- SQLite via GRDB.swift
- FTS5 for full-text search
- Keychain for credentials

**Agent Collaboration Tools Used**
- Claude Code (Anthropic)
- Codex (OpenAI)
- Commander (CodeRabbit)

**Models Used in Development**
- Claude Opus 4.5 / Sonnet 4.6
- GPT-5.4 Thinking
- Kimi K2.5 / Kimi Code

### 📝 Known Limitations

- macOS only (14.0+)
- OAuth requires manual app registration for Google/Microsoft
- CalDAV/CardDAV support varies by provider
- Single MCP session at a time (exclusive lock)

### 🔮 What's Next

Post-1.0 roadmap includes:
- Pre-configured OAuth apps (optional)
- Additional provider presets
- Improved CalDAV/CardDAV auto-discovery
- Plugin system for custom handlers

---

## About ClawMail

ClawMail is an open-source agent-first email client created by Andrew Mitchell and Max Headroom.

**Homepage:** https://clawmail.app  
**GitHub:** https://github.com/AppsAtMe/ClawMail  
**Issues:** https://github.com/AppsAtMe/ClawMail/issues  
**Discussions:** https://github.com/AppsAtMe/ClawMail/discussions

---

*For installation instructions, see [INSTALL.md](INSTALL.md) or the main README.*
