import Foundation
import Testing
import ClawMailCore
@testable import ClawMailApp

struct ConnectionTestAuthMaterialTests {

    @Test func passwordMaterialBuildsPasswordCredentials() {
        let material = ConnectionTestAuthMaterial.password("app-password")

        switch material.imapCredential(email: "user@example.com") {
        case .password(let username, let password):
            #expect(username == "user@example.com")
            #expect(password == "app-password")
        case .oauth2:
            Issue.record("Expected IMAP password credentials")
        }

        switch material.smtpCredentials() {
        case .password(let password):
            #expect(password == "app-password")
        case .oauth2:
            Issue.record("Expected SMTP password credentials")
        }

        switch material.calDAVCredential(email: "user@example.com") {
        case .password(let username, let password):
            #expect(username == "user@example.com")
            #expect(password == "app-password")
        case .oauthToken:
            Issue.record("Expected CalDAV password credentials")
        }

        switch material.cardDAVCredential(email: "user@example.com") {
        case .password(let username, let password):
            #expect(username == "user@example.com")
            #expect(password == "app-password")
        case .oauthToken:
            Issue.record("Expected CardDAV password credentials")
        }
    }

    @Test func oauthMaterialBuildsOAuthCredentials() async throws {
        let tokens = OAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let material = ConnectionTestAuthMaterial.oauth2(tokens)

        switch material.imapCredential(email: "user@example.com") {
        case .oauth2(let username, let tokenProvider):
            #expect(username == "user@example.com")
            #expect(try await tokenProvider.accessToken() == "access-token")
        case .password:
            Issue.record("Expected IMAP OAuth credentials")
        }

        switch material.smtpCredentials() {
        case .oauth2(let tokenProvider):
            #expect(try await tokenProvider.accessToken() == "access-token")
        case .password:
            Issue.record("Expected SMTP OAuth credentials")
        }

        switch material.calDAVCredential(email: "user@example.com") {
        case .oauthToken(let tokenProvider):
            #expect(try await tokenProvider.accessToken() == "access-token")
        case .password:
            Issue.record("Expected CalDAV OAuth credentials")
        }

        switch material.cardDAVCredential(email: "user@example.com") {
        case .oauthToken(let tokenProvider):
            #expect(try await tokenProvider.accessToken() == "access-token")
        case .password:
            Issue.record("Expected CardDAV OAuth credentials")
        }
    }

    @Test func oauthMaterialExposesGrantedGoogleScopes() {
        let tokens = OAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            grantedScopes: [
                "https://mail.google.com/",
                "https://www.googleapis.com/auth/calendar",
            ]
        )
        let material = ConnectionTestAuthMaterial.oauth2(tokens)

        #expect(material.grantsGoogleScope("https://www.googleapis.com/auth/calendar") == true)
        #expect(material.grantsGoogleScope("https://www.googleapis.com/auth/carddav") == false)
    }

    @Test func oauthMaterialDoesNotTreatGoogleContactsScopeAsCardDAVScope() {
        let tokens = OAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            grantedScopes: [
                "https://mail.google.com/",
                "https://www.googleapis.com/auth/contacts",
            ]
        )
        let material = ConnectionTestAuthMaterial.oauth2(tokens)

        #expect(material.grantsGoogleScope("https://www.googleapis.com/auth/contacts") == true)
        #expect(material.grantsGoogleScope("https://www.googleapis.com/auth/carddav") == false)
    }
}
