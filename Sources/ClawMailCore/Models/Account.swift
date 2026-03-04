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

public struct OAuthTokens: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}
