import Foundation

// MARK: - AppConfig

public struct AppConfig: Codable, Sendable {
    public var accounts: [Account]
    public var restApiPort: Int
    public var guardrails: GuardrailConfig
    public var syncIntervalMinutes: Int
    public var initialSyncDays: Int
    public var auditRetentionDays: Int
    public var idleFolders: [String]
    public var launchAtLogin: Bool
    public var webhookURL: String?

    public init(
        accounts: [Account] = [],
        restApiPort: Int = 24601,
        guardrails: GuardrailConfig = GuardrailConfig(),
        syncIntervalMinutes: Int = 15,
        initialSyncDays: Int = 30,
        auditRetentionDays: Int = 90,
        idleFolders: [String] = ["INBOX"],
        launchAtLogin: Bool = true,
        webhookURL: String? = nil
    ) {
        self.accounts = accounts
        self.restApiPort = restApiPort
        self.guardrails = guardrails
        self.syncIntervalMinutes = syncIntervalMinutes
        self.initialSyncDays = initialSyncDays
        self.auditRetentionDays = auditRetentionDays
        self.idleFolders = idleFolders
        self.launchAtLogin = launchAtLogin
        self.webhookURL = webhookURL
    }

    // MARK: - Persistence

    public static let defaultDirectoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClawMail")
    }()

    public static let defaultConfigURL: URL = {
        defaultDirectoryURL.appendingPathComponent("config.json")
    }()

    public static func load(from url: URL? = nil) throws -> AppConfig {
        let fileURL = url ?? defaultConfigURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfig()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppConfig.self, from: data)
    }

    public func save(to url: URL? = nil) throws {
        let fileURL = url ?? Self.defaultConfigURL
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - GuardrailConfig

public struct GuardrailConfig: Codable, Sendable {
    public var sendRateLimit: RateLimitConfig?
    public var domainAllowlist: [String]?
    public var domainBlocklist: [String]?
    public var firstTimeRecipientApproval: Bool

    public init(
        sendRateLimit: RateLimitConfig? = nil,
        domainAllowlist: [String]? = nil,
        domainBlocklist: [String]? = nil,
        firstTimeRecipientApproval: Bool = false
    ) {
        self.sendRateLimit = sendRateLimit
        self.domainAllowlist = domainAllowlist
        self.domainBlocklist = domainBlocklist
        self.firstTimeRecipientApproval = firstTimeRecipientApproval
    }
}

// MARK: - RateLimitConfig

public struct RateLimitConfig: Codable, Sendable {
    public var maxPerMinute: Int?
    public var maxPerHour: Int?
    public var maxPerDay: Int?

    public init(maxPerMinute: Int? = nil, maxPerHour: Int? = nil, maxPerDay: Int? = nil) {
        self.maxPerMinute = maxPerMinute
        self.maxPerHour = maxPerHour
        self.maxPerDay = maxPerDay
    }
}

// MARK: - SyncState

public struct SyncState: Codable, Sendable {
    public var accountLabel: String
    public var folder: String
    public var uidValidity: UInt32?
    public var highestModSeq: UInt64?
    public var lastSync: Date?

    public init(
        accountLabel: String,
        folder: String,
        uidValidity: UInt32? = nil,
        highestModSeq: UInt64? = nil,
        lastSync: Date? = nil
    ) {
        self.accountLabel = accountLabel
        self.folder = folder
        self.uidValidity = uidValidity
        self.highestModSeq = highestModSeq
        self.lastSync = lastSync
    }
}
