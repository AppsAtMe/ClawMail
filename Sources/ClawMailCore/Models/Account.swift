import Foundation

// MARK: - Account

public struct Account: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var label: String
    public var emailAddress: String
    public var displayName: String

    public var authMethod: AuthMethod
    public var imapHost: String
    public var imapPort: Int
    public var imapSecurity: ConnectionSecurity
    public var smtpHost: String
    public var smtpPort: Int
    public var smtpSecurity: ConnectionSecurity

    public var caldavURL: URL?
    public var carddavURL: URL?

    public var isEnabled: Bool
    public var lastSyncDate: Date?
    public var connectionStatus: ConnectionStatus

    public init(
        id: UUID = UUID(),
        label: String,
        emailAddress: String,
        displayName: String,
        authMethod: AuthMethod = .password,
        imapHost: String,
        imapPort: Int = 993,
        imapSecurity: ConnectionSecurity = .ssl,
        smtpHost: String,
        smtpPort: Int = 465,
        smtpSecurity: ConnectionSecurity = .ssl,
        caldavURL: URL? = nil,
        carddavURL: URL? = nil,
        isEnabled: Bool = true,
        lastSyncDate: Date? = nil,
        connectionStatus: ConnectionStatus = .disconnected
    ) {
        self.id = id
        self.label = label
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.authMethod = authMethod
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.imapSecurity = imapSecurity
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.smtpSecurity = smtpSecurity
        self.caldavURL = caldavURL
        self.carddavURL = carddavURL
        self.isEnabled = isEnabled
        self.lastSyncDate = lastSyncDate
        self.connectionStatus = connectionStatus
    }
}

// MARK: - AuthMethod

public enum AuthMethod: Codable, Sendable, Equatable {
    case password
    case oauth2(provider: OAuthProvider)
}

// MARK: - OAuthProvider

public enum OAuthProvider: String, Codable, Sendable, Equatable {
    case google
    case microsoft

    public var displayName: String {
        switch self {
        case .google: return "Google"
        case .microsoft: return "Microsoft"
        }
    }
}

// MARK: - ConnectionSecurity

public enum ConnectionSecurity: String, Codable, Sendable, Equatable {
    case ssl
    case starttls
}

// MARK: - ConnectionStatus

public enum ConnectionStatus: Codable, Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - OAuthTokens

public struct OAuthIdentity: Codable, Sendable, Equatable {
    public var subject: String
    public var email: String?
    public var emailVerified: Bool?

    public init(subject: String, email: String? = nil, emailVerified: Bool? = nil) {
        self.subject = subject
        self.email = email
        self.emailVerified = emailVerified
    }
}

public struct OAuthTokens: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var grantedScopes: [String]?
    public var identity: OAuthIdentity?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        grantedScopes: [String]? = nil,
        identity: OAuthIdentity? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.grantedScopes = grantedScopes
        self.identity = identity
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }

    public func grantsScope(_ scope: String) -> Bool? {
        guard let grantedScopes else { return nil }
        return Set(grantedScopes).contains(scope)
    }

    public var authorizedEmail: String? {
        guard let email = identity?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            return nil
        }
        return email
    }
}
