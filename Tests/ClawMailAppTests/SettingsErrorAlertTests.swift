import SwiftUI
import Testing
import ViewInspector
import ClawMailCore
@testable import ClawMailApp

@MainActor
struct SettingsErrorAlertTests {

    @Test func accountsTabRendersFailureAlertMessage() throws {
        let message = "Removing account: Server error: delete failed"
        let view = AccountsTab(
            appState: makeAppState(),
            initialErrorState: UIErrorState(message: message)
        )

        try assertOperationFailedAlert(on: view, expectedMessage: message)
    }

    @Test func apiTabRendersFailureAlertMessage() throws {
        let message = "Regenerating API key: Server error: key rotation failed"
        let view = APITab(
            appState: makeAppState(),
            initialErrorState: UIErrorState(message: message)
        )

        try assertOperationFailedAlert(on: view, expectedMessage: message)
    }

    @Test func generalTabRendersFailureAlertMessage() throws {
        let message = "The setting was saved, but updating the macOS LaunchAgent failed."
        let view = GeneralTab(
            appState: makeAppState(),
            initialErrorState: UIErrorState(message: message)
        )

        try assertOperationFailedAlert(on: view, expectedMessage: message)
    }

    @Test func activityLogTabRendersFailureAlertMessage() throws {
        let message = "Loading activity log: Server error: audit log unavailable"
        let view = ActivityLogTab(
            appState: makeAppState(),
            initialErrorState: UIErrorState(message: message)
        )

        try assertOperationFailedAlert(on: view, expectedMessage: message)
    }

    @Test func guardrailsTabRendersFailureAlertMessage() throws {
        let message = "Loading recipient approval state: Server error: metadata index unavailable"
        let view = GuardrailsTab(
            appState: makeAppState(),
            initialErrorState: UIErrorState(message: message)
        )

        try assertOperationFailedAlert(on: view, expectedMessage: message)
    }

    private func makeAppState() -> AppState {
        AppState()
    }

    private func assertOperationFailedAlert<V: View>(
        on view: V,
        expectedMessage: String
    ) throws {
        let inspected = try view.inspect()

        #expect(try inspected.find(text: "Operation Failed").string() == "Operation Failed")
        #expect(try inspected.find(text: expectedMessage).string() == expectedMessage)
        #expect(try inspected.find(button: "OK").labelView().text().string() == "OK")
    }
}
