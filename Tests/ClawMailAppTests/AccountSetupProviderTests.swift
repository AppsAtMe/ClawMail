import Testing
import ClawMailCore
@testable import ClawMailApp

struct AccountSetupProviderTests {

    @Test func providerPickerDefaultsToAppleAndKeepsExpectedOrder() {
        #expect(ProviderChoice.defaultChoice == .apple)
        #expect(ProviderChoice.allCases == [.apple, .google, .microsoft, .fastmail, .other])
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
            ProviderChoice.apple.defaultDAVSettings(emailAddress: "") == ProviderDAVSettings(
                caldavURL: "https://caldav.icloud.com",
                carddavURL: "https://contacts.icloud.com"
            )
        )
    }

    @Test func googleProviderUsesOAuthAndDerivesDAVDefaultsFromEmail() {
        #expect(ProviderChoice.google.usesOAuth == true)
        #expect(ProviderChoice.google.oauthProvider == .google)
        #expect(ProviderChoice.google.authMethod == .oauth2(provider: .google))
        #expect(
            ProviderChoice.google.defaultDAVSettings(emailAddress: "user@gmail.com") == ProviderDAVSettings(
                caldavURL: "https://apidata.googleusercontent.com/caldav/v2/user@gmail.com/user",
                carddavURL: "https://www.googleapis.com/.well-known/carddav"
            )
        )
        #expect(
            ProviderChoice.google.defaultDAVSettings(emailAddress: "") == ProviderDAVSettings(
                caldavURL: nil,
                carddavURL: "https://www.googleapis.com/.well-known/carddav"
            )
        )
    }

    @Test func fastmailProviderUsesPasswordAndDAVDefaults() {
        #expect(ProviderChoice.fastmail.usesOAuth == false)
        #expect(ProviderChoice.fastmail.oauthProvider == nil)
        #expect(ProviderChoice.fastmail.authMethod == .password)
        #expect(
            ProviderChoice.fastmail.serverSettings == ProviderServerSettings(
                imapHost: "imap.fastmail.com",
                imapPort: "993",
                imapSecurity: .ssl,
                smtpHost: "smtp.fastmail.com",
                smtpPort: "465",
                smtpSecurity: .ssl
            )
        )
        #expect(
            ProviderChoice.fastmail.defaultDAVSettings(emailAddress: "user@fastmail.com") == ProviderDAVSettings(
                caldavURL: "https://caldav.fastmail.com",
                carddavURL: "https://carddav.fastmail.com"
            )
        )
    }

    @Test func microsoftProviderKeepsBrowserSignInMetadata() {
        #expect(ProviderChoice.microsoft.usesOAuth == true)
        #expect(ProviderChoice.microsoft.oauthProvider == .microsoft)
        #expect(ProviderChoice.microsoft.authMethod == .oauth2(provider: .microsoft))
    }

    @Test func providerInferenceRecognizesExistingAppleAndFastmailAccounts() {
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

        let fastmailAccount = Account(
            label: "Fastmail",
            emailAddress: "user@fastmail.com",
            displayName: "Fastmail User",
            authMethod: .password,
            imapHost: "imap.fastmail.com",
            smtpHost: "smtp.fastmail.com"
        )

        #expect(ProviderChoice.inferred(from: fastmailAccount) == .fastmail)
    }
}
