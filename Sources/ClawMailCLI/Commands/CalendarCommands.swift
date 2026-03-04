import ArgumentParser
import ClawMailCore
import Foundation

// MARK: - Calendar Command Group

struct CalendarGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendar",
        abstract: "Calendar operations",
        subcommands: [
            CalendarCalendars.self,
            CalendarList.self,
            CalendarCreate.self,
            CalendarUpdate.self,
            CalendarDelete.self,
        ]
    )
}

// MARK: - calendar calendars

struct CalendarCalendars: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendars",
        abstract: "List available calendars"
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
        await executeRPC(socketPath: socketPath, method: "calendar.listCalendars", params: params, format: format)
    }
}

// MARK: - calendar list

struct CalendarList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List calendar events in a date range"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, help: "Start date (ISO 8601, e.g. 2025-01-01T00:00:00Z)")
    var from: String

    @Option(name: .long, help: "End date (ISO 8601, e.g. 2025-12-31T23:59:59Z)")
    var to: String

    @Option(name: .long, help: "Calendar name filter")
    var calendar: String?

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "from": .string(from),
            "to": .string(to),
        ]
        if let calendar { params["calendar"] = .string(calendar) }

        await executeRPC(socketPath: socketPath, method: "calendar.listEvents", params: params, format: format)
    }
}

// MARK: - calendar create

struct CalendarCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new calendar event"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Option(name: .long, help: "Calendar name")
    var calendar: String

    @Option(name: .long, help: "Event title")
    var title: String

    @Option(name: .long, help: "Start date/time (ISO 8601)")
    var start: String

    @Option(name: .long, help: "End date/time (ISO 8601)")
    var end: String

    @Option(name: .long, help: "Location")
    var location: String?

    @Option(name: .customLong("description"), help: "Event description")
    var eventDescription: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Attendee email addresses")
    var attendees: [String] = []

    @Option(name: .long, help: "Recurrence rule (RRULE format)")
    var recurrence: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Reminder minutes before event")
    var reminders: [Int] = []

    @Flag(name: .customLong("all-day"), help: "All-day event")
    var allDay: Bool = false

    @Option(name: .long, help: "Output format (json or text)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Custom socket path")
    var socketPath: String?

    func run() async throws {
        var params: [String: AnyCodableValue] = [
            "account": .string(account),
            "calendar": .string(calendar),
            "title": .string(title),
            "start": .string(start),
            "end": .string(end),
        ]
        if let location { params["location"] = .string(location) }
        if let eventDescription { params["description"] = .string(eventDescription) }
        if !attendees.isEmpty {
            params["attendees"] = .array(attendees.map { .string($0) })
        }
        if let recurrence { params["recurrence"] = .string(recurrence) }
        if !reminders.isEmpty {
            params["reminders"] = .array(reminders.map { .dictionary(["minutesBefore": .int($0)]) })
        }
        if allDay { params["allDay"] = .bool(true) }

        await executeRPC(socketPath: socketPath, method: "calendar.createEvent", params: params, format: format)
    }
}

// MARK: - calendar update

struct CalendarUpdate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a calendar event"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Event ID")
    var id: String

    @Option(name: .long, help: "New title")
    var title: String?

    @Option(name: .long, help: "New start date/time (ISO 8601)")
    var start: String?

    @Option(name: .long, help: "New end date/time (ISO 8601)")
    var end: String?

    @Option(name: .long, help: "New location")
    var location: String?

    @Option(name: .customLong("description"), help: "New description")
    var eventDescription: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Updated attendee emails")
    var attendees: [String] = []

    @Option(name: .long, help: "Updated recurrence rule")
    var recurrence: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Updated reminder minutes")
    var reminders: [Int] = []

    @Option(name: .long, help: "Set all-day (true/false)")
    var allDay: Bool?

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
        if let start { params["start"] = .string(start) }
        if let end { params["end"] = .string(end) }
        if let location { params["location"] = .string(location) }
        if let eventDescription { params["description"] = .string(eventDescription) }
        if !attendees.isEmpty {
            params["attendees"] = .array(attendees.map { .string($0) })
        }
        if let recurrence { params["recurrence"] = .string(recurrence) }
        if !reminders.isEmpty {
            params["reminders"] = .array(reminders.map { .dictionary(["minutesBefore": .int($0)]) })
        }
        if let allDay { params["allDay"] = .bool(allDay) }

        await executeRPC(socketPath: socketPath, method: "calendar.updateEvent", params: params, format: format)
    }
}

// MARK: - calendar delete

struct CalendarDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a calendar event"
    )

    @Option(name: .long, help: "Account label")
    var account: String

    @Argument(help: "Event ID")
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
        await executeRPC(socketPath: socketPath, method: "calendar.deleteEvent", params: params, format: format)
    }
}
