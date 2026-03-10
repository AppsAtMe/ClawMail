# OpenClaw Release Notes

## Version 1.0.0 — Initial Release

**Release Date:** March 2026  
**Status:** Stable

---

### 🎉 Initial Release

OpenClaw 1.0.0 marks our first stable release — a personal AI assistant platform designed for seamless human-agent collaboration.

### ✨ Key Features

**Core Platform**
- Multi-channel messaging (Discord, Slack, Telegram, iMessage, Signal, more)
- Session-based agent architecture with persistent memory
- Subagent spawning for parallel task execution
- Web search and content fetching capabilities
- File system integration with workspace management
- Browser automation and control

**AI Model Support**
- Anthropic Claude (Opus, Sonnet, Haiku)
- OpenAI GPT models
- Google Gemini
- Moonshot AI (Kimi)
- Local model support via Ollama

**Skills System**
- Modular skill architecture
- 30+ built-in skills including:
  - GitHub operations
  - Email management (Himalaya)
  - Calendar integration
  - Smart home control (Hue, HomeKit)
  - Media processing (video, audio, images)
  - News monitoring and summarization

**Security & Privacy**
- Local-first architecture
- 1Password integration for secrets management
- Configurable sandboxing
- No telemetry or external data collection

### 🛠️ Technical Stack

**Agent Collaboration Tools**
- Claude Code (Anthropic)
- Codex (OpenAI)
- Commander (CodeRabbit)

**Models Used in Development**
- Claude Opus 4.5 / Sonnet 4.6
- GPT-5.4 Thinking
- Kimi K2.5

**Infrastructure**
- Node.js runtime
- TypeScript
- SQLite for local data
- QMD for vector search

### 📝 Known Limitations

- OAuth configuration required for some services
- Homebrew formulas pending publication
- Windows support in development
- Some skills require additional CLI tools

### 🔮 What's Next

Post-1.0 roadmap includes:
- Pre-configured installable app with OAuth
- Expanded model support
- Enhanced agent team coordination
- Additional platform integrations

---

## About OpenClaw

OpenClaw is an open-source personal AI assistant platform created by Andrew Mitchell and Max Headroom.

**Homepage:** https://openclaw.ai  
**Documentation:** https://docs.openclaw.ai  
**Source:** https://github.com/openclaw/openclaw  
**Community:** https://discord.com/invite/clawd

---

*For installation instructions, see the main README.*
