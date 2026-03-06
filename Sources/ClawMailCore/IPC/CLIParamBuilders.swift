import Foundation

/// Pure functions that build IPC parameter dictionaries for CLI commands.
/// Extracted from CLI command structs for testability.
public enum CLIParamBuilders {

    /// Build the IPC parameter dictionary for `email.send`.
    public static func buildSendParams(
        account: String,
        to: [String],
        subject: String,
        body: String,
        cc: [String] = [],
        bcc: [String] = [],
        bodyHtml: String? = nil,
        attachments: [String] = []
    ) -> [String: AnyCodableValue] {
        let toRecipients: [AnyCodableValue] = to.map { email in
            .dictionary(["email": .string(email)])
        }

        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "to": .array(toRecipients),
            "subject": .string(subject),
            "body": .string(body),
        ]

        if !cc.isEmpty {
            params["cc"] = .array(cc.map { .dictionary(["email": .string($0)]) })
        }
        if !bcc.isEmpty {
            params["bcc"] = .array(bcc.map { .dictionary(["email": .string($0)]) })
        }
        if let bodyHtml { params["bodyHtml"] = .string(bodyHtml) }
        if !attachments.isEmpty {
            params["attachments"] = .array(attachments.map { .string($0) })
        }

        return params
    }
}
