# OpenClaw FAQ

**Frequently Asked Questions about OpenClaw**

---

## General Questions

### What is OpenClaw?

OpenClaw is a personal AI assistant platform that runs on your local machine. It connects to various messaging platforms (Discord, Slack, Telegram, etc.) and gives you an AI assistant that can read files, run commands, search the web, and perform complex tasks autonomously.

### Who created OpenClaw?

OpenClaw was created by [Andrew Mitchell](https://andrewrmitchell.com), a veteran Apple platform developer, and [Max Headroom](mailto:max@andrewrmitchell.com), his AI assistant persona. See [ABOUT.md](ABOUT.md) for more details.

### Is OpenClaw open source?

Yes. The core platform is open source and available on [GitHub](https://github.com/openclaw/openclaw).

### How much does OpenClaw cost?

OpenClaw itself is free and open source. You bring your own API keys for AI models (OpenAI, Anthropic, etc.) and pay for your own usage.

---

## Installation & Setup

### What platforms does OpenClaw support?

Currently macOS and Linux. Windows support is in development.

### How do I install OpenClaw?

See the main README for installation instructions. Quick start:
```bash
# Using Homebrew (coming soon)
brew install openclaw

# Or clone and install manually
git clone https://github.com/openclaw/openclaw.git
cd openclaw
npm install
```

### What are the system requirements?

- macOS 13+ or Linux
- Node.js 18+
- 4GB RAM minimum (8GB recommended)
- Internet connection for AI model access

### Do I need API keys?

Yes. You'll need API keys for at least one AI provider:
- OpenAI (GPT models)
- Anthropic (Claude models)
- Moonshot AI (Kimi models)
- Or a local Ollama installation

---

## Security & Privacy

### Is my data safe?

OpenClaw is local-first. Your messages, files, and data stay on your machine. No cloud processing required. No telemetry. No data collection.

### How are secrets managed?

OpenClaw integrates with 1Password for secure secret storage. API keys and credentials are never stored in plain text.

### Can OpenClaw access my files?

Yes, by design. OpenClaw has access to your workspace folder and can read/write files as needed for tasks. You control the workspace location and can restrict access as needed.

---

## Using OpenClaw

### What can OpenClaw do?

- Answer questions and have conversations
- Read and write files
- Run shell commands
- Search the web
- Control browsers
- Send messages on your behalf
- Monitor news and RSS feeds
- Manage GitHub issues and PRs
- And much more via the skills system

### How do I talk to OpenClaw?

Connect OpenClaw to a messaging platform (Discord, Slack, Telegram, etc.) and message it there. Or use the local CLI interface.

### Can OpenClaw work on its own?

Yes. OpenClaw can be configured with periodic tasks (heartbeats) to check email, monitor news, track calendars, etc., and proactively notify you of important items.

### What's a "skill"?

Skills are modular capabilities that extend OpenClaw. Examples include GitHub operations, email management, smart home control, and news monitoring. See the `skills/` directory for available skills.

---

## Troubleshooting

### OpenClaw won't start

Check that:
- Node.js is installed and up to date
- All dependencies are installed (`npm install`)
- Your config file is valid JSON
- Required API keys are configured

### AI responses are slow

Response time depends on the AI model and your internet connection. Local models (via Ollama) can be faster but may be less capable.

### How do I report bugs?

File an issue on [GitHub](https://github.com/openclaw/openclaw/issues) or ask in the [Discord](https://discord.com/invite/clawd).

---

## Advanced Topics

### Can I add my own skills?

Yes. See the skill template in `skills/skill-template/` and the [Skill Creator Guide](../skills/skill-creator/SKILL.md).

### Can OpenClaw use local AI models?

Yes, via Ollama integration. Configure a local model in your settings.

### How do subagents work?

OpenClaw can spawn isolated subagent sessions for parallel task execution. This is useful for complex workflows or tasks that should run independently.

---

## Contributing

### How can I contribute?

- File bugs and feature requests on GitHub
- Submit pull requests
- Write new skills
- Improve documentation
- Help others in Discord

### Is there a code of conduct?

Yes. Be respectful, be helpful, assume good intent. We're building tools for humans.

---

*Have a question not answered here? Ask in [Discord](https://discord.com/invite/clawd) or open a [GitHub issue](https://github.com/openclaw/openclaw/issues).*
