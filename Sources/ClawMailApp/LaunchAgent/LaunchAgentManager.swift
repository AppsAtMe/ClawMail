import Foundation

/// Manages the macOS LaunchAgent for ClawMail auto-start.
enum LaunchAgentManager {
    typealias DirectoryCreator = (URL) throws -> Void
    typealias PlistWriter = (String, URL) throws -> Void
    typealias LaunchctlRunner = ([String]) throws -> Int32
    typealias FileRemover = (URL) throws -> Void

    static let label = "com.clawmail.agent"
    static let plistFilename = "\(label).plist"
    static let installedAppExecutablePath = "/Applications/ClawMail.app/Contents/MacOS/ClawMailApp"

    static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    static var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent(plistFilename)
    }

    static var defaultProgramPath: String {
        guard let executablePath = Bundle.main.executableURL?.path,
              executablePath.hasSuffix("/ClawMailApp") else {
            return installedAppExecutablePath
        }
        return executablePath
    }

    /// Escape a string for safe inclusion in XML/plist content.
    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Generate the LaunchAgent plist content.
    static func plistContent(programPath: String = defaultProgramPath) -> String {
        let safePath = xmlEscape(programPath)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>Program</key>
            <string>\(safePath)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(safePath)</string>
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
    static func install(programPath: String = defaultProgramPath) -> Bool {
        install(
            programPath: programPath,
            launchAgentsDirectory: launchAgentsDirectory,
            plistURL: plistURL,
            createDirectory: createLaunchAgentsDirectory,
            writePlist: writePlist,
            runLaunchctl: runLaunchctl
        )
    }

    @discardableResult
    static func install(
        programPath: String,
        launchAgentsDirectory: URL,
        plistURL: URL,
        createDirectory: DirectoryCreator,
        writePlist: PlistWriter,
        runLaunchctl: LaunchctlRunner
    ) -> Bool {
        do {
            let content = plistContent(programPath: programPath)
            try createDirectory(launchAgentsDirectory)
            try writePlist(content, plistURL)
            return try runLaunchctl(["load", plistURL.path]) == 0
        } catch {
            return false
        }
    }

    /// Unload and remove the LaunchAgent plist.
    @discardableResult
    static func uninstall() -> Bool {
        uninstall(
            plistURL: plistURL,
            runLaunchctl: runLaunchctl,
            removeItem: removeLaunchAgentPlist
        )
    }

    @discardableResult
    static func uninstall(
        plistURL: URL,
        runLaunchctl: LaunchctlRunner,
        removeItem: FileRemover
    ) -> Bool {
        let unloadSucceeded: Bool
        do {
            unloadSucceeded = try runLaunchctl(["unload", plistURL.path]) == 0
        } catch {
            unloadSucceeded = false
        }

        let removeSucceeded: Bool
        do {
            try removeItem(plistURL)
            removeSucceeded = true
        } catch {
            removeSucceeded = false
        }

        return unloadSucceeded && removeSucceeded
    }

    /// Check if the LaunchAgent is currently installed.
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    private static func createLaunchAgentsDirectory(at directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private static func writePlist(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func runLaunchctl(arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func removeLaunchAgentPlist(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
