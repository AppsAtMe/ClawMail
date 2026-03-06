import Foundation
import Testing
@testable import ClawMailApp

struct LaunchAgentManagerTests {
    @Test func generatedPlistTargetsAppExecutable() throws {
        let executablePath = "/Applications/ClawMail.app/Contents/MacOS/ClawMailApp"
        let plist = LaunchAgentManager.plistContent(programPath: executablePath)
        let dictionary = try plistDictionary(data: Data(plist.utf8))

        #expect(dictionary["Program"] as? String == executablePath)
        #expect(dictionary["ProgramArguments"] as? [String] == [executablePath])
    }

    @Test func bundledTemplateTargetsAppExecutable() throws {
        let executablePath = "/Applications/ClawMail.app/Contents/MacOS/ClawMailApp"
        let resourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/com.clawmail.agent.plist")
        let dictionary = try plistDictionary(data: Data(contentsOf: resourcesURL))

        #expect(dictionary["Program"] as? String == executablePath)
        #expect(dictionary["ProgramArguments"] as? [String] == [executablePath])
    }

    @Test func installReturnsFalseWhenLaunchctlReturnsNonZero() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let plistURL = tempDir.appendingPathComponent("com.clawmail.agent.plist")

        defer { try? FileManager.default.removeItem(at: tempDir) }

        let succeeded = LaunchAgentManager.install(
            programPath: "/Applications/ClawMail.app/Contents/MacOS/ClawMailApp",
            launchAgentsDirectory: tempDir,
            plistURL: plistURL,
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            writePlist: { content, url in
                try content.write(to: url, atomically: true, encoding: .utf8)
            },
            runLaunchctl: { _ in 1 }
        )

        #expect(!succeeded)
        #expect(FileManager.default.fileExists(atPath: plistURL.path))
    }

    @Test func uninstallReturnsFalseWhenLaunchctlFails() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let plistURL = tempDir.appendingPathComponent("com.clawmail.agent.plist")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data().write(to: plistURL)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        let succeeded = LaunchAgentManager.uninstall(
            plistURL: plistURL,
            runLaunchctl: { _ in throw TestError.launchctlFailed },
            removeItem: { try FileManager.default.removeItem(at: $0) }
        )

        #expect(!succeeded)
        #expect(!FileManager.default.fileExists(atPath: plistURL.path))
    }

    @Test func uninstallReturnsFalseWhenPlistRemovalFails() throws {
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")

        let succeeded = LaunchAgentManager.uninstall(
            plistURL: plistURL,
            runLaunchctl: { _ in 0 },
            removeItem: { _ in throw TestError.removeFailed }
        )

        #expect(!succeeded)
    }

    private func plistDictionary(data: Data) throws -> [String: Any] {
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = plist as? [String: Any] else {
            throw TestError.invalidPlist
        }
        return dictionary
    }
}

private enum TestError: Error {
    case invalidPlist
    case launchctlFailed
    case removeFailed
}
