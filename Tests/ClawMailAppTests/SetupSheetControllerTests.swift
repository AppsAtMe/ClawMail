import Testing
import ClawMailCore
@testable import ClawMailApp

struct SetupSheetControllerTests {

    @Test func queuedAddPresentationClearsFlagAndStartsAddSession() {
        var controller = SetupSheetController()
        var showAccountSetup = true

        controller.presentQueuedAddIfNeeded(showAccountSetup: &showAccountSetup)

        #expect(showAccountSetup == false)
        #expect(controller.session?.mode == .add)
    }

    @Test func editPresentationStartsFreshSessionAfterAddDismissal() {
        var controller = SetupSheetController()
        let account = makeAccount()

        controller.presentAdd()
        let firstSessionID = controller.session?.id

        controller.session = nil
        controller.presentEdit(account: account)

        #expect(controller.session?.mode == .edit(account))
        #expect(controller.session?.id != firstSessionID)
    }

    @Test func editPresentationDoesNothingWithoutSelection() {
        var controller = SetupSheetController()

        controller.presentEdit(account: nil)

        #expect(controller.session == nil)
    }

    private func makeAccount() -> Account {
        Account(
            label: "work",
            emailAddress: "work@example.com",
            displayName: "Work Account",
            imapHost: "imap.example.com",
            smtpHost: "smtp.example.com"
        )
    }
}
