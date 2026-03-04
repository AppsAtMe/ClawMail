import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Tasks Command Group

struct TasksGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tasks",
        abstract: "Task operations",
        subcommands: [
            TasksTaskLists.self,
            TasksList.self,
            TasksCreate.self,
            TasksUpdate.self,
            TasksDelete.self,
        ]
    )
}

// MARK: - tasks task-lists

struct TasksTaskLists: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task-lists",
        abstract: "List available task lists"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
        ]
        await executeRPC(socketPath: socketPath, method: "tasks.listTaskLists", params: params, format: format)
    }
}

// MARK: - tasks list

struct TasksList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tasks"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("task-list"), help: "Task list name filter")
    var taskList: String?

    @Flag(name: .customLong("include-completed"), help: "Include completed tasks")
    var includeCompleted: Bool = false

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
        ]
        if let taskList { params["taskList"] = .string(taskList) }
        if includeCompleted { params["includeCompleted"] = .bool(true) }

        await executeRPC(socketPath: socketPath, method: "tasks.list", params: params, format: format)
    }
}

// MARK: - tasks create

struct TasksCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new task"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .customLong("task-list"), help: "Task list name")
    var taskList: String

    @Option(name: .long, help: "Task title")
    var title: String

    @Option(name: .customLong("description"), help: "Task description")
    var taskDescription: String?

    @Option(name: .long, help: "Due date (ISO 8601)")
    var due: String?

    @Option(name: .long, help: "Priority (low, medium, high)")
    var priority: String?

    @Option(name: .long, help: "Status (needs-action, in-process, completed, cancelled)")
    var status: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "taskList": .string(taskList),
            "title": .string(title),
        ]
        if let taskDescription { params["description"] = .string(taskDescription) }
        if let due { params["due"] = .string(due) }
        if let priority { params["priority"] = .string(priority) }
        if let status { params["status"] = .string(status) }

        await executeRPC(socketPath: socketPath, method: "tasks.create", params: params, format: format)
    }
}

// MARK: - tasks update

struct TasksUpdate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a task"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Task ID")
    var id: String

    @Option(name: .long, help: "New title")
    var title: String?

    @Option(name: .customLong("description"), help: "New description")
    var taskDescription: String?

    @Option(name: .long, help: "New due date (ISO 8601)")
    var due: String?

    @Option(name: .long, help: "New priority (low, medium, high)")
    var priority: String?

    @Option(name: .long, help: "New status (needs-action, in-process, completed, cancelled)")
    var status: String?

    @Option(name: .customLong("percent-complete"), help: "Percent complete (0-100)")
    var percentComplete: Int?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "id": .string(id),
        ]
        if let title { params["title"] = .string(title) }
        if let taskDescription { params["description"] = .string(taskDescription) }
        if let due { params["due"] = .string(due) }
        if let priority { params["priority"] = .string(priority) }
        if let status { params["status"] = .string(status) }
        if let percentComplete { params["percentComplete"] = .int(percentComplete) }

        await executeRPC(socketPath: socketPath, method: "tasks.update", params: params, format: format)
    }
}

// MARK: - tasks delete

struct TasksDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a task"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Task ID")
    var id: String

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        let params: [String: AnyCodableValue] = [
            "account": .string(account),
            "id": .string(id),
        ]
        await executeRPC(socketPath: socketPath, method: "tasks.delete", params: params, format: format)
    }
}
