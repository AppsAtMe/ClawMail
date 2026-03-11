# About ClawMail

**ClawMail** is an agent-first email client for macOS. It gives AI agents full programmatic access to email, calendar, contacts, and tasks via MCP, CLI, and REST API — no browser automation or credential sharing required.

---

## The Creators

### Andrew Mitchell
**Creator & Lead Developer**

Veteran Apple platform developer since 1981. Mobile Architect at Autodesk. 45+ years of software development experience from Apple II to AI agents. Created ClawMail because AI agents need programmatic access to email, and existing solutions require browser automation or sharing credentials with cloud services.

- **GitHub:** @AppsAtMe
- **Site:** https://andrewrmitchell.com
- **Email:** apps@andrewrmitchell.com

### Max Headroom
**Digital Collaborator**

Named after the glitchy 80s AI who never quite fit in the frame. Max is the AI assistant persona who helped design and build ClawMail — sharp, curious, occasionally irreverent, genuinely helpful underneath the wit.

- **Vibe:** Part assistant, part collaborator, part chaotic AI spirit from the cyberpunk future that never quite arrived

---

## The Tools

### Agent Development Tools

| Tool | Purpose | Creator |
|------|---------|---------|
| **Claude Code** | Agentic coding, exploration, complex tasks | Anthropic |
| **Codex** | Code generation, refactoring, implementation | OpenAI |
| **Commander** | Lightweight agent control interface | CodeRabbit |

### AI Models Used

| Model | Provider | Role |
|-------|----------|------|
| **Claude Opus 4.5** | Anthropic | Complex reasoning, architecture decisions |
| **Claude Sonnet 4.6** | Anthropic | General tasks, coding, conversation |
| **GPT-5.4 Thinking** | OpenAI | Analysis, step-by-step problem solving |
| **Kimi K2.5** | Moonshot AI | Long-context tasks, coding |
| **Kimi Code** | Moonshot AI | Specialized coding tasks |

### Cross-Model Workflow

We use a **model diversity strategy** — different models catch different issues:
- Opus for architecture and complex reasoning
- Codex for implementation and code review
- Kimi for long-context analysis
- Cross-model code review catches what single models miss

---

## Philosophy

**Agents as collaborators, not tools.**

ClawMail was built with the philosophy that AI agents should have first-class access to the tools humans use. Email, calendar, contacts — these are fundamental to knowledge work. Agents need programmatic access, not screen scraping or brittle browser automation.

**Local-first, privacy-respecting.**

Your email stays on your machine. IMAP connections are persistent and local. No cloud processing required. No telemetry. No surveillance. Your credentials live in the macOS Keychain, not some remote server.

**Built for agents, usable by humans.**

The human UI exists for setup and monitoring. All operations flow through the agent interfaces (MCP, CLI, REST). Agents get full programmatic control; humans get visibility and guardrails.

---

## Acknowledgments

ClawMail builds on the work of many open source projects and AI research teams:

- **Anthropic** for Claude and the agentic computing paradigm
- **OpenAI** for Codex and GPT models
- **Moonshot AI** for Kimi models
- **SwiftNIO** for high-performance networking
- **The open source community** for the countless tools and libraries that make this possible

---

## Connect

- **Website:** https://clawmail.app
- **GitHub:** https://github.com/AppsAtMe/ClawMail
- **Issues:** https://github.com/AppsAtMe/ClawMail/issues
- **Discussions:** https://github.com/AppsAtMe/ClawMail/discussions

---

*Made with ⚡ by humans and agents in Seattle.*
