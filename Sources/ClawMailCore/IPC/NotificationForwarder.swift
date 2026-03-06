import Foundation

/// Transforms IPC notifications into MCP-prefixed notifications for forwarding to MCP clients.
public enum NotificationForwarder {

    /// Prefix applied to IPC notification methods when forwarding to MCP.
    public static let mcpPrefix = "clawmail/"

    /// Transform an IPC notification into an MCP notification by prefixing the method name.
    public static func forwardToMCP(_ notification: JSONRPCNotification) -> JSONRPCNotification {
        JSONRPCNotification(
            method: "\(mcpPrefix)\(notification.method)",
            params: notification.params
        )
    }
}
