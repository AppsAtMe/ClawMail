# OpenClaw

**Your personal AI assistant platform. Local. Private. Yours.**

[![Discord](https://img.shields.io/discord/1476402929643552920?label=Discord&logo=discord)](https://discord.com/invite/clawd)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

OpenClaw is a personal AI assistant that runs on your own machine. Connect it to Discord, Slack, Telegram, iMessage, and more — then give it access to your files, tools, and digital life. It can read code, run commands, search the web, and work autonomously on complex tasks.

> **Note:** This is the personal workspace version. For the open-source server platform, see [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw).

---

## ✨ What It Does

- **💬 Multi-Channel Messaging** — Talk to your AI on Discord, Slack, Telegram, iMessage, Signal, WhatsApp, and more
- **📁 File System Access** — Read, write, and organize files in your workspace
- **🔧 Command Execution** — Run shell commands, scripts, and CLI tools
- **🌐 Web Integration** — Search, fetch, and interact with web content
- **🤖 Agent Teams** — Spawn subagents for parallel task execution
- **📚 Persistent Memory** — Remembers context across sessions
- **🧩 Skills System** — Extensible capabilities via modular skills
- **🔒 Privacy-First** — Runs locally, no cloud required, no telemetry

---

## 🚀 Quick Start

### Prerequisites

- macOS 13+ or Linux
- Node.js 18+
- API key from OpenAI, Anthropic, or Moonshot AI

### Installation

```bash
# Using Homebrew (coming soon)
brew install openclaw

# Or install from source
git clone https://github.com/openclaw/openclaw.git
cd openclaw
npm install
npm run build
```

### Configuration

```bash
# Copy example config
cp config.example.json config.json

# Edit with your API keys
open config.json
```

### First Run

```bash
# Start OpenClaw
openclaw start

# Or in development mode
npm run dev
```

See [docs/INSTALL.md](docs/INSTALL.md) for detailed installation instructions.

---

## 🛠️ Skills

OpenClaw's capabilities are extended through skills:

| Skill | Description |
|-------|-------------|
| **github** | Issues, PRs, code review, CI monitoring |
| **blogwatcher** | RSS/Atom feed monitoring |
| **last30days** | Social media and news research |
| **himalaya** | Email management (IMAP/SMTP) |
| **openhue** | Philips Hue light control |
| **camsnap** | RTSP/ONVIF camera capture |
| **video-frames** | Video frame extraction |
| **nano-banana-pro** | AI image generation |
| **...and more** | See `skills/` directory |

---

## 🏗️ Architecture

```
┌─────────────────┐
│  Message APIs   │ ← Discord, Slack, Telegram, etc.
└────────┬────────┘
         │
┌────────▼────────┐
│    OpenClaw     │ ← Core platform
│   ┌─────────┐   │
│   │ Session │   │ ← Message routing, state
│   │ Manager │   │
│   └────┬────┘   │
│        │        │
│   ┌────▼────┐   │
│   │  Agent  │   │ ← AI model interface
│   └────┬────┘   │
│        │        │
│   ┌────▼────┐   │
│   │ Skills  │   │ ← Modular capabilities
│   └─────────┘   │
└─────────────────┘
```

---

## 📖 Documentation

- **[Release Notes](docs/RELEASE-NOTES.md)** — Version history
- **[About](docs/ABOUT.md)** — The story, the creators, the tools
- **[FAQ](docs/FAQ.md)** — Common questions answered
- **[Installation Guide](docs/INSTALL.md)** — Detailed setup
- **[New Team Member Guide](docs/New-Team-Member-Guide.md)** — Working with AI agents

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Ways to contribute:
- Report bugs and request features
- Write new skills
- Improve documentation
- Help others in [Discord](https://discord.com/invite/clawd)

---

## 🧑‍💻 The Creators

**OpenClaw** was created by [Andrew Mitchell](https://andrewrmitchell.com) and [Max Headroom](mailto:max@andrewrmitchell.com) as an exploration in agentic software development.

See [docs/ABOUT.md](docs/ABOUT.md) for the full story.

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🔗 Links

- **Website:** https://openclaw.ai
- **Documentation:** https://docs.openclaw.ai
- **GitHub:** https://github.com/openclaw/openclaw
- **Discord:** https://discord.com/invite/clawd
- **Reddit:** r/OpenClaw

---

*Made with ⚡ by humans and agents.*
