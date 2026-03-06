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
}
