cask "clawmail" do
  version "1.0.0"
  sha256 :no_check # computed at release time

  url "https://github.com/clawmail/ClawMail/releases/download/v#{version}/ClawMail-#{version}.dmg"
  name "ClawMail"
  desc "Agent-first email client for macOS"
  homepage "https://github.com/clawmail/ClawMail"

  depends_on macos: ">= :sonoma"

  app "ClawMail.app"

  postflight do
    # Symlink CLI and MCP server to /usr/local/bin
    system_command "ln", args: ["-sf", "#{appdir}/ClawMail.app/Contents/MacOS/ClawMailCLI", "/usr/local/bin/clawmail"]
    system_command "ln", args: ["-sf", "#{appdir}/ClawMail.app/Contents/MacOS/ClawMailMCP", "/usr/local/bin/clawmail-mcp"]
  end

  uninstall launchctl: "com.clawmail.agent",
            quit:      "com.clawmail.app"

  zap trash: [
    "~/Library/Application Support/ClawMail",
    "~/Library/LaunchAgents/com.clawmail.agent.plist",
  ]
end
