import Foundation

// MARK: - VTODOParser

/// Parses and builds iCalendar VTODO components for task management.
///
/// VTODO is the iCalendar (RFC 5545) component type used for tasks/to-do items.
/// This parser handles the subset of VTODO properties that map to `TaskItem`.
public enum VTODOParser: Sendable {

    // MARK: - Parsed VTODO

    /// Structured representation of a parsed VTODO component.
    public struct ParsedVTODO: Sendable {
        public var uid: String
        public var summary: String?
        public var description: String?
        public var due: Date?
        public var priority: Int?
        public var status: String?
        public var percentComplete: Int?
        public var created: Date?
        public var lastModified: Date?

        public init(
            uid: String = "",
            summary: String? = nil,
            description: String? = nil,
            due: Date? = nil,
            priority: Int? = nil,
            status: String? = nil,
            percentComplete: Int? = nil,
            created: Date? = nil,
            lastModified: Date? = nil
        ) {
            self.uid = uid
            self.summary = summary
            self.description = description
            self.due = due
            self.priority = priority
            self.status = status
            self.percentComplete = percentComplete
            self.created = created
            self.lastModified = lastModified
        }
    }

    // MARK: - Parsing

    /// Parse iCalendar text and extract VTODO components.
    public static func parseTasks(from icalendar: String) -> [ParsedVTODO] {
        let unfolded = ICalendarParser.unfoldLines(icalendar)
        let lines = unfolded.components(separatedBy: "\n")

        var tasks: [ParsedVTODO] = []
        var current: ParsedVTODO?
        var inVTODO = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed == "BEGIN:VTODO" {
                inVTODO = true
                current = ParsedVTODO()
                continue
            }
            if trimmed == "END:VTODO" {
                if let task = current {
                    tasks.append(task)
                }
                current = nil
                inVTODO = false
                continue
            }

            guard inVTODO else { continue }

            let (key, value) = ICalendarParser.splitProperty(trimmed)
            let baseKey = key.components(separatedBy: ";").first ?? key

            switch baseKey {
            case "UID":
                current?.uid = value
            case "SUMMARY":
                current?.summary = ICalendarParser.unescapeICalValue(value)
            case "DESCRIPTION":
                current?.description = ICalendarParser.unescapeICalValue(value)
            case "DUE":
                current?.due = ICalendarDateFormatter.shared.date(from: value)
            case "PRIORITY":
                current?.priority = Int(value)
            case "STATUS":
                current?.status = value.trimmingCharacters(in: .whitespaces)
            case "PERCENT-COMPLETE":
                current?.percentComplete = Int(value)
            case "CREATED":
                current?.created = ICalendarDateFormatter.shared.date(from: value)
            case "LAST-MODIFIED":
                current?.lastModified = ICalendarDateFormatter.shared.date(from: value)
            default:
                break
            }
        }

        return tasks
    }

    // MARK: - Building

    /// Build an iCalendar VCALENDAR/VTODO string from structured data.
    public static func buildTask(
        uid: String,
        summary: String,
        description: String? = nil,
        due: Date? = nil,
        priority: Int? = nil,
        status: String = "NEEDS-ACTION",
        percentComplete: Int? = nil
    ) -> String {
        let formatter = ICalendarDateFormatter.shared
        let now = formatter.string(from: Date())

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//ClawMail//CalDAV Client//EN",
            "BEGIN:VTODO",
            "UID:\(uid)",
            "DTSTAMP:\(now)",
            "CREATED:\(now)",
            "LAST-MODIFIED:\(now)",
            "SUMMARY:\(ICalendarParser.escapeICalValue(summary))",
        ]

        if let description = description {
            lines.append("DESCRIPTION:\(ICalendarParser.escapeICalValue(description))")
        }

        if let due = due {
            lines.append("DUE:\(formatter.string(from: due))")
        }

        if let priority = priority {
            lines.append("PRIORITY:\(priority)")
        }

        lines.append("STATUS:\(status)")

        if let pc = percentComplete {
            lines.append("PERCENT-COMPLETE:\(pc)")
        }

        lines.append("END:VTODO")
        lines.append("END:VCALENDAR")

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Model Conversion Helpers

    /// Convert a `TaskPriority` enum value to an iCalendar PRIORITY integer.
    /// iCalendar priorities: 1-4 = high, 5 = medium, 6-9 = low, 0 = undefined.
    public static func icalPriority(from priority: TaskPriority?) -> Int? {
        guard let priority = priority else { return nil }
        switch priority {
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    /// Convert an iCalendar PRIORITY integer to a `TaskPriority` enum value.
    public static func taskPriority(from icalPriority: Int?) -> TaskPriority? {
        guard let p = icalPriority, p > 0 else { return nil }
        switch p {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return nil
        }
    }

    /// Convert a `TaskStatus` enum value to an iCalendar STATUS string.
    public static func icalStatus(from status: TaskStatus) -> String {
        switch status {
        case .needsAction: return "NEEDS-ACTION"
        case .inProcess: return "IN-PROCESS"
        case .completed: return "COMPLETED"
        case .cancelled: return "CANCELLED"
        }
    }

    /// Convert an iCalendar STATUS string to a `TaskStatus` enum value.
    public static func taskStatus(from icalStatus: String?) -> TaskStatus {
        guard let s = icalStatus?.trimmingCharacters(in: .whitespaces).uppercased() else {
            return .needsAction
        }
        switch s {
        case "NEEDS-ACTION": return .needsAction
        case "IN-PROCESS": return .inProcess
        case "COMPLETED": return .completed
        case "CANCELLED": return .cancelled
        default: return .needsAction
        }
    }
}
