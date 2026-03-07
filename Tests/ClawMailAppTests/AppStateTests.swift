import Testing
import ClawMailCore
@testable import ClawMailApp

@MainActor
@Suite
struct AppStateTests {

    @Test func upsertPendingAccountAddsAndTracksStatus() {
        let appState = AppState()
        let account = sampleAccount(status: .connecting)

        appState.upsertPendingAccount(account)

        #expect(appState.accounts == [account])
        #expect(appState.connectionStatuses[account.label] == .connecting)
    }

    @Test func updateConnectionStatusMutatesVisibleAccount() {
        let appState = AppState()
        let account = sampleAccount(status: .disconnected)
        appState.upsertPendingAccount(account)

        appState.updateConnectionStatus(.connected, for: account.label)

        #expect(appState.accounts.first?.connectionStatus == .connected)
        #expect(appState.connectionStatuses[account.label] == .connected)
    }

    @Test func recordActivityStoresGlobalAndPerAccountMessages() {
        let appState = AppState()

        appState.recordActivity("Mac.com connected", accountLabel: "Mac.com")

        #expect(appState.lastActivity == "Mac.com connected")
        #expect(appState.accountActivity["Mac.com"] == "Mac.com connected")
    }

    @Test func ensureSelectedSettingsAccountPrefersRequestedAccountAndFallsBackToFirst() {
        let appState = AppState()
        let first = sampleAccount(label: "Mac.com", status: .connected)
        let second = sampleAccount(label: "Work", status: .disconnected)
        appState.accounts = [first, second]

        appState.ensureSelectedSettingsAccount()
        #expect(appState.selectedSettingsAccountID == first.id)

        appState.ensureSelectedSettingsAccount(preferred: second.id)
        #expect(appState.selectedSettingsAccountID == second.id)
    }

    private func sampleAccount(label: String = "Mac.com", status: ConnectionStatus) -> Account {
        Account(
            label: label,
            emailAddress: "\(label.lowercased())@example.com",
            displayName: label,
            imapHost: "imap.mail.me.com",
            smtpHost: "smtp.mail.me.com",
            connectionStatus: status
        )
    }
}
