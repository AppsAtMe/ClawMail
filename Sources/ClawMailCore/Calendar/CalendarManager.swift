import Foundation

// MARK: - CalendarManager

/// High-level actor that provides agent-facing calendar operations.
///
/// Bridges between the agent interface (using `CalendarEvent` model objects)
/// and the underlying `CalDAVClient` (which speaks iCalendar/WebDAV).
public actor CalendarManager {

    // MARK: - Properties

    private let client: CalDAVClient

    // MARK: - Initialization

    public init(client: CalDAVClient) {
        self.client = client
    }

    // MARK: - Calendar Listing

    /// List all calendars (event-supporting) for the account.
    public func listCalendars() async throws -> [CalendarInfo] {
        let caldavCalendars = try await client.listCalendars()
        return caldavCalendars
            .filter { $0.supportsEvents }
            .map { cal in
                CalendarInfo(
                    name: cal.displayName,
                    color: cal.color,
                    isDefault: false
                )
            }
    }

    // MARK: - Event Operations

    /// List events within a date range, optionally filtered by calendar name.
    public func listEvents(from startDate: Date, to endDate: Date, calendar: String? = nil) async throws -> [CalendarEvent] {
        let calendars = try await client.listCalendars()
        let eventCalendars = calendars.filter { $0.supportsEvents }

        let targetCalendars: [CalDAVCalendar]
        if let calendarName = calendar {
            targetCalendars = eventCalendars.filter { $0.displayName == calendarName }
            if targetCalendars.isEmpty {
                throw ClawMailError.invalidParameter("Calendar '\(calendarName)' not found")
            }
        } else {
            targetCalendars = eventCalendars
        }

        var allEvents: [CalendarEvent] = []

        for cal in targetCalendars {
            let icalStrings = try await client.getEvents(calendar: cal.href, from: startDate, to: endDate)
            for icalString in icalStrings {
                let parsedEvents = ICalendarParser.parseEvents(from: icalString)
                for parsed in parsedEvents {
                    let event = calendarEvent(from: parsed, calendarName: cal.displayName)
                    allEvents.append(event)
                }
            }
        }

        return allEvents.sorted { $0.start < $1.start }
    }

    /// Create a new calendar event.
    public func createEvent(_ request: CreateEventRequest) async throws -> CalendarEvent {
        let calendars = try await client.listCalendars()
        guard let cal = calendars.first(where: { $0.displayName == request.calendar && $0.supportsEvents }) else {
            throw ClawMailError.invalidParameter("Calendar '\(request.calendar)' not found or does not support events")
        }

        let uid = UUID().uuidString
        let attendeeTuples: [(name: String?, email: String)] = (request.attendees ?? []).map { (nil, $0) }
        let reminderMinutes: [Int] = (request.reminders ?? []).map { $0.minutesBefore }

        let icalendar = ICalendarParser.buildEvent(
            uid: uid,
            summary: request.title,
            start: request.start,
            end: request.end,
            location: request.location,
            description: request.description,
            attendees: attendeeTuples,
            recurrence: request.recurrence,
            allDay: request.allDay ?? false,
            reminders: reminderMinutes
        )

        _ = try await client.createEvent(calendar: cal.href, icalendar: icalendar)

        return CalendarEvent(
            id: uid,
            calendar: request.calendar,
            title: request.title,
            start: request.start,
            end: request.end,
            location: request.location,
            description: request.description,
            attendees: (request.attendees ?? []).map { EventAttendee(email: $0) },
            recurrence: request.recurrence,
            reminders: (request.reminders ?? []),
            allDay: request.allDay ?? false
        )
    }

    /// Update an existing calendar event by ID (UID).
    public func updateEvent(id: String, _ request: UpdateEventRequest) async throws -> CalendarEvent {
        // Find the calendar that contains this event
        let calendars = try await client.listCalendars()
        let eventCalendars = calendars.filter { $0.supportsEvents }

        var foundCalendar: CalDAVCalendar?
        var foundICalString: String?

        // Search all calendars for the event with this UID
        let farPast = Date.distantPast
        let farFuture = Date.distantFuture

        for cal in eventCalendars {
            let icalStrings = try await client.getEvents(calendar: cal.href, from: farPast, to: farFuture)
            for ics in icalStrings {
                if let uid = ICalendarParser.extractUID(from: ics), uid == id {
                    foundCalendar = cal
                    foundICalString = ics
                    break
                }
            }
            if foundCalendar != nil { break }
        }

        guard let cal = foundCalendar, let existingICS = foundICalString else {
            throw ClawMailError.invalidParameter("Event with ID '\(id)' not found")
        }

        // Parse existing event and apply updates
        let existingEvents = ICalendarParser.parseEvents(from: existingICS)
        guard let existing = existingEvents.first else {
            throw ClawMailError.serverError("Failed to parse existing event")
        }

        let newTitle = request.title ?? existing.summary ?? ""
        let newStart = request.start ?? existing.dtstart ?? Date()
        let newEnd = request.end ?? existing.dtend ?? Date()
        let newLocation = request.location ?? existing.location
        let newDescription = request.description ?? existing.description
        let newRecurrence = request.recurrence ?? existing.recurrence
        let newAllDay = request.allDay ?? existing.allDay

        let attendeeTuples: [(name: String?, email: String)]
        if let requestAttendees = request.attendees {
            attendeeTuples = requestAttendees.map { (nil, $0) }
        } else {
            attendeeTuples = existing.attendees.map { ($0.name, $0.email) }
        }

        let reminderMinutes: [Int]
        if let requestReminders = request.reminders {
            reminderMinutes = requestReminders.map { $0.minutesBefore }
        } else {
            reminderMinutes = existing.reminders
        }

        let updatedICal = ICalendarParser.buildEvent(
            uid: id,
            summary: newTitle,
            start: newStart,
            end: newEnd,
            location: newLocation,
            description: newDescription,
            attendees: attendeeTuples,
            recurrence: newRecurrence,
            allDay: newAllDay,
            reminders: reminderMinutes
        )

        try await client.updateEvent(calendar: cal.href, uid: id, icalendar: updatedICal)

        let updatedAttendees: [EventAttendee]
        if let requestAttendees = request.attendees {
            updatedAttendees = requestAttendees.map { EventAttendee(email: $0) }
        } else {
            updatedAttendees = existing.attendees.map { att in
                EventAttendee(
                    name: att.name,
                    email: att.email,
                    status: attendeeStatus(from: att.status)
                )
            }
        }

        return CalendarEvent(
            id: id,
            calendar: cal.displayName,
            title: newTitle,
            start: newStart,
            end: newEnd,
            location: newLocation,
            description: newDescription,
            attendees: updatedAttendees,
            recurrence: newRecurrence,
            reminders: (request.reminders ?? existing.reminders.map { EventReminder(minutesBefore: $0) }),
            allDay: newAllDay
        )
    }

    /// Delete an event by ID (UID).
    public func deleteEvent(id: String) async throws {
        let calendars = try await client.listCalendars()
        let eventCalendars = calendars.filter { $0.supportsEvents }

        let farPast = Date.distantPast
        let farFuture = Date.distantFuture

        for cal in eventCalendars {
            let icalStrings = try await client.getEvents(calendar: cal.href, from: farPast, to: farFuture)
            for ics in icalStrings {
                if let uid = ICalendarParser.extractUID(from: ics), uid == id {
                    try await client.deleteEvent(calendar: cal.href, uid: id)
                    return
                }
            }
        }

        throw ClawMailError.invalidParameter("Event with ID '\(id)' not found")
    }

    // MARK: - Private Helpers

    /// Convert a parsed iCalendar event into a CalendarEvent model.
    private func calendarEvent(from parsed: ICalendarParser.ParsedEvent, calendarName: String) -> CalendarEvent {
        let attendees = parsed.attendees.map { att in
            EventAttendee(
                name: att.name,
                email: att.email,
                status: attendeeStatus(from: att.status)
            )
        }

        let reminders = parsed.reminders.map { EventReminder(minutesBefore: $0) }

        return CalendarEvent(
            id: parsed.uid,
            calendar: calendarName,
            title: parsed.summary ?? "",
            start: parsed.dtstart ?? Date(),
            end: parsed.dtend ?? Date(),
            location: parsed.location,
            description: parsed.description,
            attendees: attendees,
            recurrence: parsed.recurrence,
            reminders: reminders,
            allDay: parsed.allDay
        )
    }

    /// Map iCalendar PARTSTAT value to AttendeeStatus enum.
    private func attendeeStatus(from partstat: String) -> AttendeeStatus {
        switch partstat.uppercased() {
        case "ACCEPTED": return .accepted
        case "DECLINED": return .declined
        case "TENTATIVE": return .tentative
        default: return .needsAction
        }
    }
}
