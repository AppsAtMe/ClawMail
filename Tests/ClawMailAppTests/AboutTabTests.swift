import SwiftUI
import Testing
import ViewInspector
import ClawMailCore
@testable import ClawMailApp

@MainActor
struct AboutTabTests {

    @Test func aboutTabRendersMetadataAndRuntimeSummary() async throws {
        let appState = makeAppState()
        appState.accounts = [sampleAccount(label: "work"), sampleAccount(label: "personal")]
        appState.agentConnected = true
        appState.isRunning = true

        let details = makeDetails()
        let sut = AboutTab(
            appState: appState,
            details: details,
            revealAction: { _ in },
            copySupportAction: { _ in }
        )

        try await ViewHosting.host(sut.environment(appState)) {
            try await sut.inspection.inspect(after: .milliseconds(50)) { view in
                let textValues = view.findAll(ViewType.Text.self).compactMap { try? $0.string() }

                #expect(textValues.contains(details.appName))
                #expect(textValues.contains("Version \(details.version)"))
                #expect(textValues.contains("Build \(details.build)"))
                #expect(textValues.contains(details.bundleIdentifier))
                #expect(textValues.contains(details.configURL.path))
                #expect(textValues.contains("Connected"))
                #expect(textValues.contains("Healthy"))
            }
        }
    }

    @Test func aboutTabSupportButtonsInvokeProvidedActions() async throws {
        let appState = makeAppState()
        let details = makeDetails()
        var revealedURLs: [URL] = []
        var copiedSupportSummaries: [String] = []

        let sut = AboutTab(
            appState: appState,
            details: details,
            revealAction: { revealedURLs.append($0) },
            copySupportAction: { copiedSupportSummaries.append($0) }
        )

        try await ViewHosting.host(sut.environment(appState)) {
            try await sut.inspection.inspect { view in
                try findButton(in: view, label: "Open Support Folder").tap()
                try findButton(in: view, label: "Copy Support Info").tap()
                try findButton(in: view, label: "Reveal Config File").tap()
            }
        }

        #expect(revealedURLs == [details.supportDirectoryURL, details.configURL])
        #expect(copiedSupportSummaries == [details.supportSummary])
    }

    private func makeAppState() -> AppState {
        AppState()
    }

    private func makeDetails() -> AboutAppDetails {
        AboutAppDetails(
            appName: "ClawMail",
            version: "9.9.9",
            build: "42",
            bundleIdentifier: "com.example.clawmail",
            minimumSystemVersion: "14.0",
            supportDirectoryURL: URL(fileURLWithPath: "/tmp/ClawMail"),
            configURL: URL(fileURLWithPath: "/tmp/ClawMail/config.json"),
            databaseURL: URL(fileURLWithPath: "/tmp/ClawMail/metadata.sqlite"),
            copyright: "MIT"
        )
    }

    private func sampleAccount(label: String) -> Account {
        Account(
            label: label,
            emailAddress: "\(label)@example.com",
            displayName: "\(label.capitalized) Account",
            imapHost: "imap.example.com",
            smtpHost: "smtp.example.com"
        )
    }

    private func findButton<V: View>(
        in view: InspectableView<ViewType.View<V>>,
        label: String
    ) throws -> InspectableView<ViewType.Button> {
        guard let button = view.findAll(ViewType.Button.self).first(where: {
            (try? $0.labelView().text().string()) == label
        }) else {
            throw TestError.buttonNotFound(label)
        }
        return button
    }

    private enum TestError: Error {
        case buttonNotFound(String)
    }
}
