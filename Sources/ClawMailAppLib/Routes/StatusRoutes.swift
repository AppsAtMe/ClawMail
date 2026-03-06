import Foundation
import Hummingbird
import ClawMailCore

// MARK: - StatusRoutes

/// Route group for status and account management endpoints.
enum StatusRoutes {

    static func register(on router: Router<BasicRequestContext>, orchestrator: AccountOrchestrator) {

        // GET /api/v1/status — daemon health check (no auth required)
        router.get("api/v1/status") { request, context -> Response in
            let status = DaemonStatus(
                status: "running",
                version: "1.0.0",
                agentConnected: await orchestrator.isAgentConnected,
                uptime: ProcessInfo.processInfo.systemUptime
            )
            return jsonResponse(status)
        }

        // GET /api/v1/accounts — list configured accounts
        router.get("api/v1/accounts") { request, context -> Response in
            let accounts = await orchestrator.listAccounts()
            return jsonResponse(accounts.map { AccountSummary(from: $0) })
        }

        // GET /api/v1/accounts/:label/status — per-account status
        router.get("api/v1/accounts/:label/status") { request, context -> Response in
            await handleRoute {
                guard let label = context.parameters.get("label") else {
                    return badRequestResponse("Missing account label")
                }
                guard let account = await orchestrator.getAccount(label: label) else {
                    throw ClawMailError.accountNotFound(label)
                }
                return jsonResponse(AccountSummary(from: account))
            }
        }
    }
}

// MARK: - Response Types

/// Daemon status response for GET /api/v1/status.
struct DaemonStatus: Codable, Sendable {
    var status: String
    var version: String
    var agentConnected: Bool
    var uptime: Double
}

/// Account summary for GET /api/v1/accounts.
struct AccountSummary: Codable, Sendable {
    var label: String
    var emailAddress: String
    var displayName: String
    var isEnabled: Bool
    var connectionStatus: ConnectionStatus
    var lastSyncDate: Date?
    var hasCalDAV: Bool
    var hasCardDAV: Bool

    init(from account: Account) {
        self.label = account.label
        self.emailAddress = account.emailAddress
        self.displayName = account.displayName
        self.isEnabled = account.isEnabled
        self.connectionStatus = account.connectionStatus
        self.lastSyncDate = account.lastSyncDate
        self.hasCalDAV = account.caldavURL != nil
        self.hasCardDAV = account.carddavURL != nil
    }
}
