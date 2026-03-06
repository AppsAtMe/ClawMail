import SwiftUI
import Testing
import ViewInspector
import ClawMailCore
@testable import ClawMailApp

extension Inspection: InspectionEmissary { }

@MainActor
struct SettingsInteractionTests {

    @Test func apiTabShowsFailureAlertWhenRegenerationFails() async throws {
        let appState = makeAppState()
        let sut = APITab(
            appState: appState,
            generateAPIKeyAction: {
                throw ClawMailError.serverError("key rotation failed")
            }
        )

        try await ViewHosting.host(sut.environment(appState)) {
            try await sut.inspection.inspect { view in
                try findButton(in: view, label: "Regenerate").tap()
            }

            try await sut.inspection.inspect(after: .milliseconds(50)) { view in
                try assertOperationFailedAlert(
                    on: view,
                    expectedMessage: "Regenerating API key: Server error: key rotation failed"
                )
            }
        }
    }

    @Test func activityLogTabShowsFailureAlertWhenInitialLoadFails() async throws {
        let appState = makeAppState(accounts: [sampleAccount()])
        let sut = ActivityLogTab(
            appState: appState,
            loadEntriesAction: { _, _ in
                throw ClawMailError.serverError("audit log unavailable")
            }
        )

        try await ViewHosting.host(sut.environment(appState)) {
            try await sut.inspection.inspect(after: .milliseconds(50)) { view in
                try assertOperationFailedAlert(
                    on: view,
                    expectedMessage: "Loading activity log: Server error: audit log unavailable"
                )
            }
        }
    }

    @Test func guardrailsTabShowsFailureAlertWhenApprovalLoadFails() async throws {
        let appState = makeAppState()
        let sut = GuardrailsTab(
            appState: appState,
            loadApprovalStateAction: { _ in
                throw ClawMailError.serverError("metadata index unavailable")
            }
        )

        try await ViewHosting.host(sut.environment(appState)) {
            try await sut.inspection.inspect(after: .milliseconds(50)) { view in
                try assertOperationFailedAlert(
                    on: view,
                    expectedMessage: "Loading recipient approval state: Server error: metadata index unavailable"
                )
            }
        }
    }

    @Test func generalTabShowsFailureAlertWhenLaunchAtLoginUpdateFails() async throws {
        let account = sampleAccount()
        let appState = makeAppState(accounts: [account], config: AppConfig(accounts: [account], launchAtLogin: false))
        let sut = GeneralTab(
            appState: appState,
            saveConfigAction: { _ in },
            installLaunchAgent: { false },
            uninstallLaunchAgent: { true }
        )

        try await ViewHosting.host(sut.environment(appState)) {
            try await sut.inspection.inspect { view in
                try findToggle(in: view, label: "Launch at login").tap()
            }

            try await sut.inspection.inspect(after: .milliseconds(50)) { view in
                try assertOperationFailedAlert(
                    on: view,
                    expectedMessage: "The setting was saved, but updating the macOS LaunchAgent failed."
                )
            }
        }
    }

    private func makeAppState(accounts: [Account] = [], config: AppConfig = AppConfig()) -> AppState {
        let appState = AppState()
        appState.accounts = accounts
        appState.config = config
        appState.isRunning = true
        return appState
    }

    private func sampleAccount(label: String = "work") -> Account {
        Account(
            label: label,
            emailAddress: "\(label)@example.com",
            displayName: "Work Account",
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

    private func findToggle<V: View>(
        in view: InspectableView<ViewType.View<V>>,
        label: String
    ) throws -> InspectableView<ViewType.Toggle> {
        guard let toggle = view.findAll(ViewType.Toggle.self).first(where: {
            (try? $0.labelView().text().string()) == label
        }) else {
            throw TestError.toggleNotFound(label)
        }
        return toggle
    }

    private func assertOperationFailedAlert<V: View>(
        on view: InspectableView<ViewType.View<V>>,
        expectedMessage: String
    ) throws {
        let textValues = view.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        let buttonLabels = view.findAll(ViewType.Button.self).compactMap { try? $0.labelView().text().string() }

        #expect(textValues.contains("Operation Failed"))
        #expect(textValues.contains(expectedMessage))
        #expect(buttonLabels.contains("OK"))
    }

    private enum TestError: Error {
        case buttonNotFound(String)
        case toggleNotFound(String)
    }
}
