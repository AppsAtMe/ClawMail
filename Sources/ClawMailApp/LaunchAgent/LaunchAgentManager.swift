import Foundation

/// Manages the macOS LaunchAgent for ClawMail auto-start.
enum LaunchAgentManager {
    static let label = "com.clawmail.agent"
    static let plistFilename = "\(label).plist"

    static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    static var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent(plistFilename)
    }

    /// Generate the LaunchAgent plist content.
    static func plistContent(programPath: String = "/usr/local/bin/clawmail") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>Program</key>
            <string>\(programPath)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(programPath)</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/tmp/clawmail.stdout.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/clawmail.stderr.log</string>
            <key>ProcessType</key>
            <string>Background</string>
        </dict>
        </plist>
        """
    }

    /// Install the LaunchAgent plist and load it.
    @discardableResult
    static func install(programPath: String = "/usr/local/bin/clawmail") -> Bool {
        do {
            // Ensure LaunchAgents directory exists
            try FileManager.default.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )

            // Write plist
            let content = plistContent(programPath: programPath)
            try content.write(to: plistURL, atomically: true, encoding: .utf8)

            // Load with launchctl
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["load", plistURL.path]
            try process.run()
            process.waitUntilExit()

            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Unload and remove the LaunchAgent plist.
    @discardableResult
    static func uninstall() -> Bool {
        // Unload with launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]
        try? process.run()
        process.waitUntilExit()

        // Remove plist file
        try? FileManager.default.removeItem(at: plistURL)

        return true
    }

    /// Check if the LaunchAgent is currently installed.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }
}
