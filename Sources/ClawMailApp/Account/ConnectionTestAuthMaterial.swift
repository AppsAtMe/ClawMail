import ClawMailCore

enum ConnectionTestAuthMaterial: Sendable {
    case password(String)
    case oauth2(OAuthTokens)

    func imapCredential(email: String) -> IMAPCredential {
        switch self {
        case .password(let password):
            return .password(username: email, password: password)
        case .oauth2(let tokens):
            return .oauth2(username: email, tokenProvider: .constant(tokens.accessToken))
        }
    }

    func smtpCredentials() -> Credentials {
        switch self {
        case .password(let password):
            return .password(password)
        case .oauth2(let tokens):
            return .oauth2(tokenProvider: .constant(tokens.accessToken))
        }
    }

    func calDAVCredential(email: String) -> CalDAVCredential {
        switch self {
        case .password(let password):
            return .password(username: email, password: password)
        case .oauth2(let tokens):
            return .oauthToken(.constant(tokens.accessToken))
        }
    }

    func cardDAVCredential(email: String) -> CardDAVCredential {
        switch self {
        case .password(let password):
            return .password(username: email, password: password)
        case .oauth2(let tokens):
            return .oauthToken(.constant(tokens.accessToken))
        }
    }
}
