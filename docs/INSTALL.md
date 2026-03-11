# Installation Guide

**Getting ClawMail up and running on your Mac**

---

## System Requirements

### Supported Platforms
- **macOS** 14.0 (Sonoma) or later
- **Linux** — Future support planned
- **Windows** — Not currently supported

### Hardware
- **RAM:** 4GB minimum, 8GB recommended
- **Storage:** 500MB for installation
- **Network:** Internet connection for email sync

### Software Prerequisites
- **Swift 6** toolchain (Xcode 16+)
- **Git** 2.30 or later
- **Docker** (optional, for integration tests)

---

## Step 1: Install Prerequisites

### macOS

**Xcode Command Line Tools:**
```bash
xcode-select --install
```

**Verify Swift:**
```bash
swift --version  # Should be 6.0 or later
```

**Install Git (if not already installed):**
```bash
brew install git
```

---

## Step 2: Install ClawMail

### From Source

```bash
# Clone the repository
git clone https://github.com/AppsAtMe/ClawMail.git
cd ClawMail

# Build and install
make install
```

This builds a release binary, creates `ClawMail.app`, and installs it to `/Applications/ClawMail.app`.

If `/usr/local/bin` is writable, `make install` also symlinks the CLI tools:

| Symlink | Points to |
|---------|-----------|
| `/usr/local/bin/clawmail` | `ClawMail.app/Contents/MacOS/ClawMailCLI` |
| `/usr/local/bin/clawmail-mcp` | `ClawMail.app/Contents/MacOS/ClawMailMCP` |

If `/usr/local/bin` is not writable, you can either:
- Rerun with `make install BIN_DIR="$HOME/.local/bin"`
- Use the executables directly: `/Applications/ClawMail.app/Contents/MacOS/ClawMailCLI`
- Create symlinks manually with `sudo`

---

## Step 3: First Run

### Launch ClawMail

```bash
# Launch the app
open /Applications/ClawMail.app
```

ClawMail runs as a menu bar icon (no Dock icon). On first launch with no accounts, it automatically opens Settings to the Accounts tab.

### Add Your First Account

1. Click the ClawMail menu bar icon
2. Open **Settings** → **Accounts**
3. Click **+** to add an account
4. Select your provider:
   - **Apple / iCloud** — App-specific password required
   - **Google** — OAuth2 browser sign-in
   - **Microsoft 365 / Outlook** — OAuth2 browser sign-in
   - **Fastmail** — App password
   - **Other** — Manual IMAP/SMTP setup

5. Follow the setup wizard:
   - Enter credentials
   - Test connection
   - Set a label (e.g., `work`, `personal`)

See [ACCOUNTS.md](ACCOUNTS.md) for detailed setup instructions for each provider.

---

## Step 4: Connect an AI Agent (Optional)

### Claude Code

Add to your `.mcp.json`:
```json
{
  "mcpServers": {
    "clawmail": {
      "command": "/Applications/ClawMail.app/Contents/MacOS/ClawMailMCP"
    }
  }
}
```

### Other Agents

ClawMail exposes:
- **MCP** (stdio) — For Claude and compatible agents
- **CLI** — For terminal workflows
- **REST API** — For custom integrations

See the main README for details.

---

## Uninstalling

```bash
make uninstall
```

Removes the app, symlinks, and LaunchAgent.

---

## Troubleshooting

**Build fails:**
- Ensure Xcode 16+ is installed
- Run `swift build` to see detailed errors

**Cannot connect to email:**
- See [ACCOUNTS.md](ACCOUNTS.md) for provider-specific troubleshooting

**Permission denied:**
- You may need to grant ClawMail permissions in System Settings → Privacy & Security

---

*Need help? Open a [GitHub Discussion](https://github.com/AppsAtMe/ClawMail/discussions).*
