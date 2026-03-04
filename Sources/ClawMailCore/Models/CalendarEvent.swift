import Foundation

// MARK: - CalendarInfo

public struct CalendarInfo: Codable, Sendable, Equatable {
    public var name: String
    public var color: String?
    public var isDefault: Bool

    public init(name: String, color: String? = nil, isDefault: Bool = false) {
        self.name = name
        self.color = color
        self.isDefault = isDefault
    }
}

// MARK: - CalendarEvent

public struct CalendarEvent: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var calendar: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var description: String?
    public var attendees: [EventAttendee]
    public var recurrence: String?
    public var reminders: [EventReminder]
    public var allDay: Bool

    public init(
        id: String,
        calendar: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        description: String? = nil,
        attendees: [EventAttendee] = [],
        recurrence: String? = nil,
        reminders: [EventReminder] = [],
        allDay: Bool = false
    ) {
        self.id = id
        self.calendar = calendar
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.description = description
        self.attendees = attendees
        self.recurrence = recurrence
        self.reminders = reminders
        self.allDay = allDay
    }
}

// MARK: - EventAttendee

public struct EventAttendee: Codable, Sendable, Equatable {
    public var name: String?
    public var email: String
    public var status: AttendeeStatus

    public init(name: String? = nil, email: String, status: AttendeeStatus = .needsAction) {
        self.name = name
        self.email = email
        self.status = status
    }
}

public enum AttendeeStatus: String, Codable, Sendable, Equatable {
    case accepted
    case declined
    case tentative
    case needsAction = "needs-action"
}

// MARK: - EventReminder

public struct EventReminder: Codable, Sendable, Equatable {
    public var minutesBefore: Int

    public init(minutesBefore: Int) {
        self.minutesBefore = minutesBefore
    }
}

// MARK: - CreateEventRequest

public struct CreateEventRequest: Codable, Sendable {
    public var account: String
    public var calendar: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var description: String?
    public var attendees: [String]?
    public var recurrence: String?
    public var reminders: [EventReminder]?
    public var allDay: Bool?

    public init(
        account: String,
        calendar: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        description: String? = nil,
        attendees: [String]? = nil,
        recurrence: String? = nil,
        reminders: [EventReminder]? = nil,
        allDay: Bool? = nil
    ) {
        self.account = account
        self.calendar = calendar
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.description = description
        self.attendees = attendees
        self.recurrence = recurrence
        self.reminders = reminders
        self.allDay = allDay
    }
}

// MARK: - UpdateEventRequest

public struct UpdateEventRequest: Codable, Sendable {
    public var account: String
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var location: String?
    public var description: String?
    public var attendees: [String]?
    public var recurrence: String?
    public var reminders: [EventReminder]?
    public var allDay: Bool?

    public init(
        account: String,
        title: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        location: String? = nil,
        description: String? = nil,
        attendees: [String]? = nil,
        recurrence: String? = nil,
        reminders: [EventReminder]? = nil,
        allDay: Bool? = nil
    ) {
        self.account = account
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.description = description
        self.attendees = attendees
        self.recurrence = recurrence
        self.reminders = reminders
        self.allDay = allDay
    }
}
