# Installation Guide

**Getting OpenClaw up and running on your machine**

---

## System Requirements

### Supported Platforms
- **macOS** 13 (Ventura) or later
- **Linux** — Ubuntu 22.04+, Debian 11+, Fedora 35+
- **Windows** — In development (WSL2 recommended for now)

### Hardware
- **RAM:** 4GB minimum, 8GB recommended
- **Storage:** 2GB for installation, more for models/data
- **Network:** Broadband connection for AI API calls

### Software Prerequisites
- **Node.js** 18.0 or later
- **npm** 9.0 or later (comes with Node)
- **Git** 2.30 or later
- **Homebrew** (macOS recommended)

---

## Step 1: Install Prerequisites

### macOS

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js
brew install node

# Verify installations
node --version  # Should be v18+ or v20+
npm --version   # Should be 9+
```

### Linux (Ubuntu/Debian)

```bash
# Update package list
sudo apt update

# Install Node.js from NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install Git
sudo apt install -y git

# Verify
node --version
npm --version
git --version
```

### Linux (Fedora)

```bash
# Install Node.js
sudo dnf install -y nodejs npm

# Install Git
sudo dnf install -y git

# Verify
node --version
npm --version
```

---

## Step 2: Get API Keys

OpenClaw needs at least one AI provider API key:

### Option A: OpenAI (Recommended for GPT models)

1. Go to [platform.openai.com](https://platform.openai.com)
2. Create an account or sign in
3. Go to **API keys** → **Create new secret key**
4. Copy the key (you won't see it again)

### Option B: Anthropic (Recommended for Claude)

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Create an account
3. Go to **API keys** → **Create Key**
4. Copy the key

### Option C: Moonshot AI (Kimi models)

1. Go to [platform.moonshot.cn](https://platform.moonshot.cn)
2. Create an account
3. Generate API key in dashboard

### Option D: Local Models (Ollama)

If you prefer local AI without API calls:

```bash
# Install Ollama
brew install ollama  # macOS
# or
curl -fsSL https://ollama.com/install.sh | sh  # Linux

# Pull a model
ollama pull llama3.2
ollama pull qwen2.5
```

---

## Step 3: Install OpenClaw

### Method 1: Homebrew (Recommended — Coming Soon)

```bash
# Tap the OpenClaw repository
brew tap openclaw/tap

# Install OpenClaw
brew install openclaw
```

### Method 2: From Source

```bash
# Clone the repository
git clone https://github.com/openclaw/openclaw.git
cd openclaw

# Install dependencies
npm install

# Build the project
npm run build

# Link for global access (optional)
npm link
```

### Method 3: Using npx (No Install)

```bash
# Run directly without installing
npx openclaw start
```

---

## Step 4: Configure OpenClaw

### Create Config File

```bash
# Copy the example config
cp config.example.json ~/.openclaw/config.json

# Or let OpenClaw create one on first run
openclaw init
```

### Edit Configuration

```bash
# Open config in your editor
open ~/.openclaw/config.json
```

Minimum configuration:

```json
{
  "ai": {
    "defaultProvider": "anthropic",
    "providers": {
      "anthropic": {
        "apiKey": "sk-ant-...your-key..."
      }
    }
  },
  "channels": {
    "discord": {
      "enabled": true,
      "token": "...your-discord-bot-token..."
    }
  }
}
```

See [CONFIGURATION.md](CONFIGURATION.md) for all options.

---

## Step 5: First Run

### Start OpenClaw

```bash
# If installed via Homebrew or npm link
openclaw start

# If running from source
npm start

# Development mode (with hot reload)
npm run dev
```

### Verify It's Working

1. Send a message to your connected channel (Discord, etc.)
2. Or use the CLI:
   ```bash
   openclaw status
   ```

You should see:
```
✓ OpenClaw is running
✓ Connected to Discord
✓ AI provider: anthropic/claude-sonnet-4.6
✓ 12 skills loaded
```

---

## Step 6: Optional Setup

### 1Password Integration (Recommended)

For secure secret management:

```bash
# Install 1Password CLI
brew install 1password-cli

# Sign in
op signin

# Configure OpenClaw to use 1Password
# Edit ~/.openclaw/config.json:
{
  "secrets": {
    "backend": "1password",
    "vault": "OpenClaw"
  }
}
```

### QMD Memory System (Optional)

For better local memory search:

```bash
# Install bun runtime
curl -fsSL https://bun.sh/install | bash

# Install QMD
bun install -g qmd

# Run setup
openclaw setup qmd
```

See [QMD-SETUP.md](QMD-SETUP.md) for details.

### Skills Setup

Some skills need additional configuration:

```bash
# List available skills
openclaw skills list

# Enable a skill
openclaw skills enable github
openclaw skills enable blogwatcher

# Configure skill settings
openclaw skills config github
```

---

## Troubleshooting

### "Cannot find module" errors

```bash
# Reinstall dependencies
rm -rf node_modules
npm install
npm run build
```

### API key errors

```bash
# Verify your key is set
cat ~/.openclaw/config.json | grep apiKey

# Test the key manually
curl https://api.anthropic.com/v1/models \
  -H "x-api-key: your-key-here"
```

### Port already in use

```bash
# Find what's using port 3000
lsof -i :3000

# Kill it or change OpenClaw port in config
```

### Discord bot not responding

1. Check bot token is correct
2. Verify bot has "Message Content Intent" enabled in Discord Developer Portal
3. Ensure bot has permissions in your server

### Still stuck?

- Check [FAQ.md](FAQ.md)
- Ask in [Discord](https://discord.com/invite/clawd)
- Open a [GitHub issue](https://github.com/openclaw/openclaw/issues)

---

## Next Steps

- Read the [New Team Member Guide](New-Team-Member-Guide.md)
- Explore available [skills](../skills/)
- Set up [periodic tasks](../HEARTBEAT.md)
- Customize your [SOUL.md](../SOUL.md) and [USER.md](../USER.md)

---

## Uninstalling

```bash
# If installed via Homebrew
brew uninstall openclaw

# If installed from source
cd openclaw
npm unlink  # if linked
rm -rf ~/clawd  # or your workspace
```

---

*Need help? Join us on [Discord](https://discord.com/invite/clawd)*
