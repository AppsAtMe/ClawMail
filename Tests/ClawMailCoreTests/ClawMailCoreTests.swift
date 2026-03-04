import Testing
@testable import ClawMailCore

@Test func versionExists() {
    #expect(ClawMailVersion.current == "0.1.0")
}
