import Foundation
import Testing
import ClawMailCore
@testable import ClawMailApp

struct AccountSetupCredentialStateTests {

    @Test func editingPasswordAccountReusesSavedPasswordAfterPreload() {
        let account = Account(
            label: "Personal",
            emailAddress: "user@example.com",
            displayName: "Example User",
            authMethod: .password,
            imapHost: "imap.mail.me.com",
            smtpHost: "smtp.mail.me.com"
        )

        let state = AccountSetupCredentialState(
            existingAccount: account,
            provider: .apple,
            enteredPassword: "",
            enteredOAuthTokens: nil,
            storedPassword: "saved-app-password",
            storedOAuthTokens: nil,
            storedCredentialsDidLoad: true
        )

        #expect(state.passwordCredentialsReady == true)
        #expect(state.oauthCredentialsReady == false)
        #expect(state.editCredentialStatus == .savedPasswordReady)

        switch state.connectionTestAuthMaterial {
        case .password(let password):
            #expect(password == "saved-app-password")
        case .oauth2:
            Issue.record("Expected saved password auth material")
        }
    }

    @Test func editingOAuthAccountWaitsForStoredTokensBeforeReusingThem() {
        let account = Account(
            label: "Google",
            emailAddress: "user@gmail.com",
            displayName: "Example User",
            authMethod: .oauth2(provider: .google),
            imapHost: "imap.gmail.com",
            smtpHost: "smtp.gmail.com"
        )

        let loadingState = AccountSetupCredentialState(
            existingAccount: account,
            provider: .google,
            enteredPassword: "",
            enteredOAuthTokens: nil,
            storedPassword: nil,
            storedOAuthTokens: nil,
            storedCredentialsDidLoad: false
        )

        #expect(loadingState.oauthCredentialsReady == false)
        #expect(loadingState.editCredentialStatus == .loadingSavedOAuth)

        let tokens = OAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        )

        let readyState = AccountSetupCredentialState(
            existingAccount: account,
            provider: .google,
            enteredPassword: "",
            enteredOAuthTokens: nil,
            storedPassword: nil,
            storedOAuthTokens: tokens,
            storedCredentialsDidLoad: true
        )

        #expect(readyState.oauthCredentialsReady == true)
        #expect(readyState.editCredentialStatus == .savedOAuthReady)

        switch readyState.connectionTestAuthMaterial {
        case .oauth2(let storedTokens):
            #expect(storedTokens.accessToken == "access-token")
            #expect(storedTokens.refreshToken == "refresh-token")
        case .password:
            Issue.record("Expected saved OAuth auth material")
        }
    }

    @Test func changingProvidersInEditModeRequiresFreshCredentials() {
        let account = Account(
            label: "Personal",
            emailAddress: "user@example.com",
            displayName: "Example User",
            authMethod: .password,
            imapHost: "imap.mail.me.com",
            smtpHost: "smtp.mail.me.com"
        )

        let state = AccountSetupCredentialState(
            existingAccount: account,
            provider: .google,
            enteredPassword: "",
            enteredOAuthTokens: nil,
            storedPassword: "saved-app-password",
            storedOAuthTokens: nil,
            storedCredentialsDidLoad: true
        )

        #expect(state.passwordCredentialsReady == false)
        #expect(state.oauthCredentialsReady == false)
        #expect(state.editCredentialStatus == .browserSignInRequired)
    }
}
