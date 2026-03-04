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
            let summaries = accounts.map { account in
                AccountSummary(
                    label: account.label,
                    emailAddress: account.emailAddress,
                    displayName: account.displayName,
                    isEnabled: account.isEnabled,
                    connectionStatus: account.connectionStatus,
                    lastSyncDate: account.lastSyncDate,
                    hasCalDAV: account.caldavURL != nil,
                    hasCardDAV: account.carddavURL != nil
                )
            }
            return jsonResponse(summaries)
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
}
