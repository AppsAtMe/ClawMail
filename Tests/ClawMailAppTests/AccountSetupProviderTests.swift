import Testing
import ClawMailCore
@testable import ClawMailApp

struct AccountSetupProviderTests {

    @Test func providerPickerDefaultsToAppleAndKeepsExpectedOrder() {
        #expect(ProviderChoice.defaultChoice == .apple)
        #expect(ProviderChoice.allCases == [.apple, .google, .microsoft, .other])
    }

    @Test func appleProviderUsesPasswordAndICloudDefaults() {
        #expect(ProviderChoice.apple.usesOAuth == false)
        #expect(ProviderChoice.apple.oauthProvider == nil)
        #expect(ProviderChoice.apple.authMethod == .password)
        #expect(
            ProviderChoice.apple.serverSettings == ProviderServerSettings(
                imapHost: "imap.mail.me.com",
                imapPort: "993",
                imapSecurity: .ssl,
                smtpHost: "smtp.mail.me.com",
                smtpPort: "587",
                smtpSecurity: .starttls
            )
        )
        #expect(
            ProviderChoice.apple.davSettings == ProviderDAVSettings(
                caldavURL: "https://caldav.icloud.com",
                carddavURL: "https://contacts.icloud.com"
            )
        )
    }

    @Test func oauthProvidersKeepBrowserSignInMetadata() {
        #expect(ProviderChoice.google.usesOAuth == true)
        #expect(ProviderChoice.google.oauthProvider == .google)
        #expect(ProviderChoice.google.authMethod == .oauth2(provider: .google))

        #expect(ProviderChoice.microsoft.usesOAuth == true)
        #expect(ProviderChoice.microsoft.oauthProvider == .microsoft)
        #expect(ProviderChoice.microsoft.authMethod == .oauth2(provider: .microsoft))
    }

    @Test func providerInferenceRecognizesExistingAppleAccounts() {
        let appleAccount = Account(
            label: "Mac.com",
            emailAddress: "amitchell@mac.com",
            displayName: "Andrew Mitchell",
            authMethod: .password,
            imapHost: "imap.mail.me.com",
            smtpHost: "smtp.mail.me.com"
        )

        #expect(ProviderChoice.inferred(from: appleAccount) == .apple)
        #expect(AccountSetupMode.edit(appleAccount).isEditing == true)
    }
}
