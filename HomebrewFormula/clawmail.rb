cask "clawmail" do
  version "1.0.0"
  sha256 :no_check # computed at release time

  url "https://github.com/AppsAtMe/ClawMail/releases/download/v#{version}/ClawMail-#{version}.dmg"
  name "ClawMail"
  desc "Agent-first email client for macOS"
  homepage "https://github.com/AppsAtMe/ClawMail"

  depends_on macos: ">= :sonoma"

  app "ClawMail.app"
  binary "#{appdir}/ClawMail.app/Contents/MacOS/ClawMailCLI", target: "clawmail"
  binary "#{appdir}/ClawMail.app/Contents/MacOS/ClawMailMCP", target: "clawmail-mcp"

  uninstall launchctl: "com.clawmail.agent",
            quit:      "com.clawmail.app"

  zap trash: [
    "~/Library/Application Support/ClawMail",
    "~/Library/LaunchAgents/com.clawmail.agent.plist",
  ]
end
