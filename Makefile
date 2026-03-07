.PHONY: build release test bundle sign notarize dmg install uninstall clean test-infra-up test-infra-down

# ──────────────────────────────────────────────
# Configuration (override on command line)
# ──────────────────────────────────────────────
VERSION        ?= 1.0.0
SIGNING_ID     ?= -
TEAM_ID        ?=
ENTITLEMENTS   := Sources/ClawMailApp/Resources/ClawMail.entitlements
APP_BUNDLE     := build/ClawMail.app
APP_INSTALL_DIR ?= /Applications
BIN_DIR        ?= /usr/local/bin
APP_INSTALL_PATH = $(APP_INSTALL_DIR)/ClawMail.app
CLI_INSTALL_PATH = $(APP_INSTALL_PATH)/Contents/MacOS/ClawMailCLI
MCP_INSTALL_PATH = $(APP_INSTALL_PATH)/Contents/MacOS/ClawMailMCP
DMG_NAME       := ClawMail-$(VERSION).dmg
DMG_PATH       := build/$(DMG_NAME)

# ──────────────────────────────────────────────
# Build
# ──────────────────────────────────────────────
build:
	swift build

release:
	swift build -c release

test:
	swift test

# ──────────────────────────────────────────────
# App Bundle
# ──────────────────────────────────────────────
bundle: release
	@echo "Creating $(APP_BUNDLE)..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@# Copy executables
	@cp .build/release/ClawMailApp  $(APP_BUNDLE)/Contents/MacOS/ClawMailApp
	@cp .build/release/ClawMailCLI  $(APP_BUNDLE)/Contents/MacOS/ClawMailCLI
	@cp .build/release/ClawMailMCP  $(APP_BUNDLE)/Contents/MacOS/ClawMailMCP
	@# Copy metadata
	@cp Sources/ClawMailApp/Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp Sources/ClawMailApp/Resources/ClawMail.entitlements $(APP_BUNDLE)/Contents/Resources/
	@cp Resources/com.clawmail.agent.plist $(APP_BUNDLE)/Contents/Resources/
	@echo "Bundle created at $(APP_BUNDLE)"

# ──────────────────────────────────────────────
# Code Signing
# ──────────────────────────────────────────────
# Usage:
#   make sign                           # ad-hoc sign (default, for local dev)
#   make sign SIGNING_ID="Developer ID Application: Name (TEAMID)"
sign: bundle
	@echo "Signing with identity: $(SIGNING_ID)"
	@codesign --force --options runtime --timestamp \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGNING_ID)" \
		$(APP_BUNDLE)/Contents/MacOS/ClawMailCLI
	@codesign --force --options runtime --timestamp \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGNING_ID)" \
		$(APP_BUNDLE)/Contents/MacOS/ClawMailMCP
	@codesign --force --options runtime --timestamp \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGNING_ID)" \
		$(APP_BUNDLE)
	@echo "Signed. Verifying..."
	@codesign --verify --deep --strict $(APP_BUNDLE)
	@echo "Signature valid."

# ──────────────────────────────────────────────
# DMG
# ──────────────────────────────────────────────
dmg: sign
	@echo "Creating $(DMG_PATH)..."
	@rm -f $(DMG_PATH)
	@hdiutil create -volname "ClawMail" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		$(DMG_PATH)
	@# Sign the DMG itself if using a real identity
	@if [ "$(SIGNING_ID)" != "-" ]; then \
		codesign --force --timestamp --sign "$(SIGNING_ID)" $(DMG_PATH); \
	fi
	@echo "DMG created at $(DMG_PATH)"

# ──────────────────────────────────────────────
# Notarization
# ──────────────────────────────────────────────
# Usage:
#   make notarize TEAM_ID=XXXXXXXXXX
#
# Requires:
#   - Valid "Developer ID Application" signing identity
#   - App-specific password stored in Keychain as "notarytool-password"
#     (xcrun notarytool store-credentials "notarytool-password" ...)
notarize: dmg
ifndef TEAM_ID
	$(error TEAM_ID is required. Usage: make notarize TEAM_ID=XXXXXXXXXX SIGNING_ID="Developer ID Application: ...")
endif
	@echo "Submitting $(DMG_PATH) for notarization..."
	@xcrun notarytool submit $(DMG_PATH) \
		--keychain-profile "notarytool-password" \
		--team-id $(TEAM_ID) \
		--wait
	@echo "Stapling notarization ticket..."
	@xcrun stapler staple $(DMG_PATH)
	@echo "Notarization complete."

# ──────────────────────────────────────────────
# Install / Uninstall
# ──────────────────────────────────────────────
install: bundle
	@echo "Installing ClawMail..."
	@mkdir -p "$(APP_INSTALL_DIR)"
	@rm -rf "$(APP_INSTALL_PATH)"
	@cp -R "$(APP_BUNDLE)" "$(APP_INSTALL_PATH)"
	@if mkdir -p "$(BIN_DIR)" 2>/dev/null && [ -w "$(BIN_DIR)" ]; then \
		if ln -sf "$(CLI_INSTALL_PATH)" "$(BIN_DIR)/clawmail" && \
		   ln -sf "$(MCP_INSTALL_PATH)" "$(BIN_DIR)/clawmail-mcp"; then \
			echo "Installed app to $(APP_INSTALL_PATH)"; \
			echo "Installed CLI symlinks in $(BIN_DIR)"; \
			echo "Run 'clawmail' from terminal."; \
		else \
			echo "Installed app to $(APP_INSTALL_PATH)"; \
			echo "Could not create CLI symlinks in $(BIN_DIR)."; \
			echo "Use $(CLI_INSTALL_PATH) directly, or rerun with BIN_DIR=\$$HOME/.local/bin."; \
			echo "You can also create symlinks manually with sudo if you want them in $(BIN_DIR)."; \
		fi; \
	else \
		echo "Installed app to $(APP_INSTALL_PATH)"; \
		echo "Skipping CLI symlinks because $(BIN_DIR) is not writable."; \
		echo "Use $(CLI_INSTALL_PATH) directly, or rerun with BIN_DIR=\$$HOME/.local/bin."; \
		echo "You can also create symlinks manually with sudo if you want them in $(BIN_DIR)."; \
	fi

uninstall:
	@echo "Uninstalling ClawMail..."
	@launchctl unload ~/Library/LaunchAgents/com.clawmail.agent.plist 2>/dev/null || true
	@rm -f ~/Library/LaunchAgents/com.clawmail.agent.plist
	@if [ -w "$(BIN_DIR)" ]; then \
		rm -f "$(BIN_DIR)/clawmail"; \
		rm -f "$(BIN_DIR)/clawmail-mcp"; \
	elif [ -e "$(BIN_DIR)/clawmail" ] || [ -L "$(BIN_DIR)/clawmail" ] || \
	     [ -e "$(BIN_DIR)/clawmail-mcp" ] || [ -L "$(BIN_DIR)/clawmail-mcp" ]; then \
		echo "Skipping CLI symlink removal because $(BIN_DIR) is not writable."; \
		echo "Remove them manually with sudo if needed."; \
	fi
	@rm -rf "$(APP_INSTALL_PATH)"
	@echo "Uninstalled."

# ──────────────────────────────────────────────
# Clean
# ──────────────────────────────────────────────
clean:
	swift package clean
	rm -rf build/

# ──────────────────────────────────────────────
# Test Infrastructure (Docker)
# ──────────────────────────────────────────────
test-infra-up:
	docker compose up -d

test-infra-down:
	docker compose down

test-all: test-infra-up
	swift test
	$(MAKE) test-infra-down
