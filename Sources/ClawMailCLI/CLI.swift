import ArgumentParser
import ClawMailCore

@main
struct ClawMailCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clawmail",
        abstract: "ClawMail — Agent-first email client for macOS",
        version: ClawMailVersion.current,
        subcommands: [
            EmailGroup.self,
            CalendarGroup.self,
            ContactsGroup.self,
            TasksGroup.self,
            AccountsGroup.self,
            AuditGroup.self,
            StatusCommand.self,
            RecipientsGroup.self,
        ]
    )
}
