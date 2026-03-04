import Foundation

// MARK: - TaskList

public struct TaskList: Codable, Sendable, Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

// MARK: - TaskItem

public struct TaskItem: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var taskList: String
    public var title: String
    public var description: String?
    public var due: Date?
    public var priority: TaskPriority?
    public var status: TaskStatus
    public var percentComplete: Int
    public var created: Date
    public var modified: Date

    public init(
        id: String,
        taskList: String,
        title: String,
        description: String? = nil,
        due: Date? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus = .needsAction,
        percentComplete: Int = 0,
        created: Date = Date(),
        modified: Date = Date()
    ) {
        self.id = id
        self.taskList = taskList
        self.title = title
        self.description = description
        self.due = due
        self.priority = priority
        self.status = status
        self.percentComplete = percentComplete
        self.created = created
        self.modified = modified
    }
}

// MARK: - TaskPriority

public enum TaskPriority: String, Codable, Sendable, Equatable {
    case low
    case medium
    case high
}

// MARK: - TaskStatus

public enum TaskStatus: String, Codable, Sendable, Equatable {
    case needsAction = "needs-action"
    case inProcess = "in-process"
    case completed
    case cancelled
}

// MARK: - CreateTaskRequest

public struct CreateTaskRequest: Codable, Sendable {
    public var account: String
    public var taskList: String
    public var title: String
    public var description: String?
    public var due: Date?
    public var priority: TaskPriority?
    public var status: TaskStatus?

    public init(
        account: String,
        taskList: String,
        title: String,
        description: String? = nil,
        due: Date? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus? = nil
    ) {
        self.account = account
        self.taskList = taskList
        self.title = title
        self.description = description
        self.due = due
        self.priority = priority
        self.status = status
    }
}

// MARK: - UpdateTaskRequest

public struct UpdateTaskRequest: Codable, Sendable {
    public var account: String
    public var title: String?
    public var description: String?
    public var due: Date?
    public var priority: TaskPriority?
    public var status: TaskStatus?
    public var percentComplete: Int?

    public init(
        account: String,
        title: String? = nil,
        description: String? = nil,
        due: Date? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus? = nil,
        percentComplete: Int? = nil
    ) {
        self.account = account
        self.title = title
        self.description = description
        self.due = due
        self.priority = priority
        self.status = status
        self.percentComplete = percentComplete
    }
}
