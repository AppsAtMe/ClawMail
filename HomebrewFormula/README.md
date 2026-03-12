# Homebrew Tap for ClawMail

## Installation

```bash
# Add the tap
brew tap AppsAtMe/clawmail https://github.com/AppsAtMe/ClawMail

# Install ClawMail
brew install --cask clawmail
```

## Uninstallation

```bash
brew uninstall --cask clawmail
brew untap AppsAtMe/clawmail
```

## Release Process (for maintainers)

1. Build signed & notarized DMG:
   ```bash
   make dmg SIGNING_ID="Developer ID Application: Your Name (TEAMID)" TEAM_ID=XXXXXXXXXX
   ```

2. Create GitHub release with DMG attached

3. Compute SHA256:
   ```bash
   shasum -a 256 ClawMail-1.0.0.dmg
   ```

4. Update `clawmail.rb` with the SHA256

5. Push to main

## Submitting to Homebrew Cask (optional)

Once you have stable releases, you can submit to the official Homebrew Cask repo:

```bash
brew create --cask https://github.com/AppsAtMe/ClawMail/releases/download/v1.0.0/ClawMail-1.0.0.dmg
# Then submit PR to Homebrew/homebrew-cask
```

This removes the need for users to add a custom tap.
