# ClawMail FAQ

**Frequently Asked Questions about ClawMail**

---

## General Questions

### What is ClawMail?

ClawMail is an agent-first email client for macOS. It gives AI agents full programmatic access to email, calendar, contacts, and tasks via MCP (Model Context Protocol), CLI, and REST API — no browser automation or credential sharing required.

### Who created ClawMail?

ClawMail was created by [Andrew Mitchell](https://andrewrmitchell.com), a veteran Apple platform developer, with help from Max Headroom, his AI assistant persona. See [ABOUT.md](ABOUT.md) for more details.

### Is ClawMail open source?

Yes. ClawMail is open source and available on [GitHub](https://github.com/AppsAtMe/ClawMail).

### How much does ClawMail cost?

ClawMail is free and open source. You run it on your own machine with your own email accounts.

---

## Installation & Setup

### What platforms does ClawMail support?

macOS 14.0 (Sonoma) or later. Linux and Windows support may come in the future.

### How do I install ClawMail?

```bash
git clone https://github.com/AppsAtMe/ClawMail.git
cd ClawMail
make install
```

This builds ClawMail and installs it to `/Applications/ClawMail.app`.

### What are the system requirements?

- macOS 14.0+
- Swift 6 toolchain (Xcode 16+)
- 4GB RAM minimum (8GB recommended)
- Docker (optional, for integration tests)

---

## Security & Privacy

### Is my data safe?

Yes. ClawMail is local-first:
- Your email stays on your machine
- Credentials are stored in the macOS Keychain
- No cloud processing required
- No telemetry or data collection

### How are passwords managed?

Passwords and app-specific passwords are stored securely in the macOS Keychain via the KeychainAccess library. OAuth tokens are also stored in Keychain.

### Can ClawMail read all my email?

ClawMail can access whatever email accounts you configure. You control which accounts to add and can remove them at any time.

---

## Using ClawMail

### What can ClawMail do?

- **Email:** Read, send, search, manage folders (IMAP/SMTP)
- **Calendar:** List, create, update events (CalDAV)
- **Contacts:** Search, create, update contacts (CardDAV)
- **Tasks:** Manage todo items (VTODO via CalDAV)

All operations are available through three interfaces:
- **MCP** — For AI agents (Claude, etc.)
- **CLI** — For terminal workflows
- **REST API** — For custom integrations

### How do I add an email account?

1. Launch ClawMail (menu bar icon)
2. Open Settings → Accounts
3. Click "+" to add an account
4. Select your provider (Google, Microsoft, Apple, Fastmail, or Other)
5. Follow the setup wizard

See [ACCOUNTS.md](ACCOUNTS.md) for detailed setup instructions.

### What providers are supported?

- **Google** (Gmail) — OAuth2
- **Microsoft 365 / Outlook** — OAuth2
- **Apple / iCloud** — App-specific password
- **Fastmail** — App password
- **Other** — Any IMAP/SMTP provider

---

## Agent Interfaces

### What is MCP?

MCP (Model Context Protocol) is a protocol for AI agents to interact with tools. ClawMail exposes 34 MCP tools for email, calendar, contacts, and tasks. AI agents like Claude can use these tools to manage your email programmatically.

### How do I connect Claude to ClawMail?

Add to your Claude Code `.mcp.json`:
```json
{
  "mcpServers": {
    "clawmail": {
      "command": "/Applications/ClawMail.app/Contents/MacOS/ClawMailMCP"
    }
  }
}
```

### Can I use the CLI without an AI agent?

Yes. The CLI works independently:
```bash
clawmail email list --account=work --folder=INBOX
clawmail email send --account=work --to="alice@example.com" --subject="Hello"
clawmail calendar list --account=work --from=2026-03-01 --to=2026-03-31
```

---

## Troubleshooting

### I can't connect to my email server

See [ACCOUNTS.md](ACCOUNTS.md) for provider-specific troubleshooting. Common issues:
- Check IMAP/SMTP server settings
- Verify you're using an app-specific password (not your regular password)
- Check firewall settings

### OAuth sign-in fails

- Ensure your OAuth app is configured as a "Desktop app"
- Check that redirect URIs match
- Verify your account is added as a test user (for personal accounts)

### CalDAV/CardDAV doesn't work

Not all providers support CalDAV/CardDAV:
- Google — Requires enabling CalDAV API in Cloud Console
- Microsoft — DAV support varies by tenant
- Apple/Fastmail — Usually works with default settings

See [ACCOUNTS.md](ACCOUNTS.md) for details.

---

## Contributing

### How can I contribute?

- Report bugs and request features on GitHub
- Submit pull requests
- Improve documentation
- Help others in Discussions

### Is there a code of conduct?

Yes. Be respectful, be helpful, assume good intent.

---

*Have a question not answered here? Open a [GitHub Discussion](https://github.com/AppsAtMe/ClawMail/discussions) or [Issue](https://github.com/AppsAtMe/ClawMail/issues).*
