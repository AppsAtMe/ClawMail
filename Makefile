.PHONY: build release test install uninstall clean dmg

# Build debug
build:
	swift build

# Build release
release:
	swift build -c release

# Run tests
test:
	swift test

# Build app bundle
bundle: release
	@echo "Creating ClawMail.app bundle..."
	@mkdir -p build/ClawMail.app/Contents/MacOS
	@mkdir -p build/ClawMail.app/Contents/Resources
	@cp .build/release/ClawMailApp build/ClawMail.app/Contents/MacOS/ClawMailApp
	@cp .build/release/ClawMailCLI build/ClawMail.app/Contents/MacOS/ClawMailCLI
	@cp .build/release/ClawMailMCP build/ClawMail.app/Contents/MacOS/ClawMailMCP
	@cp Sources/ClawMailApp/Resources/Info.plist build/ClawMail.app/Contents/Info.plist
	@cp Resources/com.clawmail.agent.plist build/ClawMail.app/Contents/Resources/
	@echo "Bundle created at build/ClawMail.app"

# Install locally (development)
install: bundle
	@echo "Installing ClawMail..."
	@cp -r build/ClawMail.app /Applications/
	@ln -sf /Applications/ClawMail.app/Contents/MacOS/ClawMailCLI /usr/local/bin/clawmail
	@ln -sf /Applications/ClawMail.app/Contents/MacOS/ClawMailMCP /usr/local/bin/clawmail-mcp
	@echo "Installed. Run 'clawmail' from terminal."

# Uninstall
uninstall:
	@echo "Uninstalling ClawMail..."
	@launchctl unload ~/Library/LaunchAgents/com.clawmail.agent.plist 2>/dev/null || true
	@rm -f ~/Library/LaunchAgents/com.clawmail.agent.plist
	@rm -f /usr/local/bin/clawmail
	@rm -f /usr/local/bin/clawmail-mcp
	@rm -rf /Applications/ClawMail.app
	@echo "Uninstalled."

# Clean build artifacts
clean:
	swift package clean
	rm -rf build/

# Start test infrastructure
test-infra-up:
	docker compose up -d

# Stop test infrastructure
test-infra-down:
	docker compose down
