import Foundation

// MARK: - TaskManager

/// High-level actor that provides agent-facing task (VTODO) operations.
///
/// Bridges between the agent interface (using `TaskItem` model objects)
/// and the underlying `CalDAVClient` (which speaks iCalendar VTODO/WebDAV).
public actor TaskManager {

    // MARK: - Properties

    private let client: CalDAVClient

    // MARK: - Initialization

    public init(client: CalDAVClient) {
        self.client = client
    }

    // MARK: - Task List Operations

    /// List all task lists (CalDAV calendars that support VTODO).
    public func listTaskLists() async throws -> [TaskList] {
        let caldavLists = try await client.listTaskLists()
        return caldavLists.map { TaskList(name: $0.displayName) }
    }

    // MARK: - Task Operations

    /// List tasks, optionally filtered by task list name.
    public func listTasks(
        taskList: String? = nil,
        includeCompleted: Bool = false,
        sort: SortOrder = .dateDescending
    ) async throws -> [TaskItem] {
        let allTaskLists = try await client.listTaskLists()

        let targetLists: [CalDAVCalendar]
        if let listName = taskList {
            targetLists = allTaskLists.filter { $0.displayName == listName }
            if targetLists.isEmpty {
                throw ClawMailError.invalidParameter("Task list '\(listName)' not found")
            }
        } else {
            targetLists = allTaskLists
        }

        var allTasks: [TaskItem] = []

        for list in targetLists {
            let icalStrings = try await client.getTasks(taskList: list.href, includeCompleted: includeCompleted)
            for icalString in icalStrings {
                let parsedTodos = VTODOParser.parseTasks(from: icalString)
                for parsed in parsedTodos {
                    let task = taskItem(from: parsed, taskListName: list.displayName)
                    allTasks.append(task)
                }
            }
        }

        // Sort by due date or creation date
        switch sort {
        case .dateAscending:
            allTasks.sort { lhs, rhs in
                let lhsDate = lhs.due ?? lhs.created
                let rhsDate = rhs.due ?? rhs.created
                return lhsDate < rhsDate
            }
        case .dateDescending:
            allTasks.sort { lhs, rhs in
                let lhsDate = lhs.due ?? lhs.created
                let rhsDate = rhs.due ?? rhs.created
                return lhsDate > rhsDate
            }
        }

        return allTasks
    }

    /// Create a new task.
    public func createTask(_ request: CreateTaskRequest) async throws -> TaskItem {
        let taskLists = try await client.listTaskLists()
        guard let list = taskLists.first(where: { $0.displayName == request.taskList }) else {
            throw ClawMailError.invalidParameter("Task list '\(request.taskList)' not found or does not support tasks")
        }

        let uid = UUID().uuidString
        let status = request.status ?? .needsAction

        let icalendar = VTODOParser.buildTask(
            uid: uid,
            summary: request.title,
            description: request.description,
            due: request.due,
            priority: VTODOParser.icalPriority(from: request.priority),
            status: VTODOParser.icalStatus(from: status),
            percentComplete: nil
        )

        _ = try await client.createTask(taskList: list.href, icalendar: icalendar)

        let now = Date()
        return TaskItem(
            id: uid,
            taskList: request.taskList,
            title: request.title,
            description: request.description,
            due: request.due,
            priority: request.priority,
            status: status,
            percentComplete: 0,
            created: now,
            modified: now
        )
    }

    /// Update an existing task by ID (UID).
    public func updateTask(id: String, _ request: UpdateTaskRequest) async throws -> TaskItem {
        // Find the task list containing this task
        let taskLists = try await client.listTaskLists()

        var foundList: CalDAVCalendar?
        var foundICalString: String?

        for list in taskLists {
            let icalStrings = try await client.getTasks(taskList: list.href, includeCompleted: true)
            for ics in icalStrings {
                let parsed = VTODOParser.parseTasks(from: ics)
                if parsed.contains(where: { $0.uid == id }) {
                    foundList = list
                    foundICalString = ics
                    break
                }
            }
            if foundList != nil { break }
        }

        guard let list = foundList, let existingICS = foundICalString else {
            throw ClawMailError.invalidParameter("Task with ID '\(id)' not found")
        }

        // Parse existing task and apply updates
        let existingTodos = VTODOParser.parseTasks(from: existingICS)
        guard let existing = existingTodos.first(where: { $0.uid == id }) else {
            throw ClawMailError.serverError("Failed to parse existing task")
        }

        let newTitle = request.title ?? existing.summary ?? ""
        let newDescription = request.description ?? existing.description
        let newDue = request.due ?? existing.due
        let newStatus = request.status ?? VTODOParser.taskStatus(from: existing.status)
        let newPriority = request.priority ?? VTODOParser.taskPriority(from: existing.priority)
        let newPercentComplete = request.percentComplete ?? existing.percentComplete

        let updatedICal = VTODOParser.buildTask(
            uid: id,
            summary: newTitle,
            description: newDescription,
            due: newDue,
            priority: VTODOParser.icalPriority(from: newPriority),
            status: VTODOParser.icalStatus(from: newStatus),
            percentComplete: newPercentComplete
        )

        try await client.updateTask(taskList: list.href, uid: id, icalendar: updatedICal)

        return TaskItem(
            id: id,
            taskList: list.displayName,
            title: newTitle,
            description: newDescription,
            due: newDue,
            priority: newPriority,
            status: newStatus,
            percentComplete: newPercentComplete ?? 0,
            created: existing.created ?? Date(),
            modified: Date()
        )
    }

    /// Delete a task by ID (UID).
    public func deleteTask(id: String) async throws {
        let taskLists = try await client.listTaskLists()

        for list in taskLists {
            let icalStrings = try await client.getTasks(taskList: list.href, includeCompleted: true)
            for ics in icalStrings {
                let parsed = VTODOParser.parseTasks(from: ics)
                if parsed.contains(where: { $0.uid == id }) {
                    try await client.deleteTask(taskList: list.href, uid: id)
                    return
                }
            }
        }

        throw ClawMailError.invalidParameter("Task with ID '\(id)' not found")
    }

    // MARK: - Private Helpers

    /// Convert a parsed VTODO into a TaskItem model.
    private func taskItem(from parsed: VTODOParser.ParsedVTODO, taskListName: String) -> TaskItem {
        TaskItem(
            id: parsed.uid,
            taskList: taskListName,
            title: parsed.summary ?? "",
            description: parsed.description,
            due: parsed.due,
            priority: VTODOParser.taskPriority(from: parsed.priority),
            status: VTODOParser.taskStatus(from: parsed.status),
            percentComplete: parsed.percentComplete ?? 0,
            created: parsed.created ?? Date(),
            modified: parsed.lastModified ?? Date()
        )
    }
}
