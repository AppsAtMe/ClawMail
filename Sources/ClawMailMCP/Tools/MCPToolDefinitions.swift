import Foundation
import ClawMailCore

// MARK: - MCP Tool Definition

/// Represents an MCP tool definition with JSON Schema input.
struct MCPToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: AnyCodableValue
    /// The corresponding IPC method name (e.g., "email.list").
    let ipcMethod: String

    /// Convert to MCP wire format dictionary.
    func toMCPValue() -> AnyCodableValue {
        .dictionary([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema,
        ])
    }
}

// MARK: - JSON Schema Helpers

/// Convenience builders for JSON Schema fragments used in tool definitions.
enum Schema {
    static func object(
        properties: [String: AnyCodableValue],
        required: [String] = []
    ) -> AnyCodableValue {
        var dict: [String: AnyCodableValue] = [
            "type": .string("object"),
            "properties": .dictionary(properties),
        ]
        if !required.isEmpty {
            dict["required"] = .array(required.map { .string($0) })
        }
        return .dictionary(dict)
    }

    static func string(_ description: String) -> AnyCodableValue {
        .dictionary([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    static func integer(_ description: String) -> AnyCodableValue {
        .dictionary([
            "type": .string("integer"),
            "description": .string(description),
        ])
    }

    static func boolean(_ description: String) -> AnyCodableValue {
        .dictionary([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }

    static func array(_ description: String, items: AnyCodableValue) -> AnyCodableValue {
        .dictionary([
            "type": .string("array"),
            "description": .string(description),
            "items": items,
        ])
    }
}

// MARK: - All Tool Definitions

/// Registry of all MCP tools exposed by the ClawMail MCP server.
enum MCPTools {

    /// All available tool definitions.
    static let all: [MCPToolDefinition] = emailTools + calendarTools + contactsTools + tasksTools + adminTools

    /// Lookup table from tool name to definition for fast dispatch.
    static let byName: [String: MCPToolDefinition] = {
        var map = [String: MCPToolDefinition]()
        for tool in all {
            map[tool.name] = tool
        }
        return map
    }()

    // MARK: - Email Tools

    static let emailTools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "email_list",
            description: "List email messages in a folder",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "folder": Schema.string("Folder name (default: INBOX)"),
                    "limit": Schema.integer("Maximum number of messages to return"),
                    "offset": Schema.integer("Offset for pagination"),
                ],
                required: ["account"]
            ),
            ipcMethod: "email.list"
        ),
        MCPToolDefinition(
            name: "email_read",
            description: "Read a specific email message by ID",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Message ID"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "email.read"
        ),
        MCPToolDefinition(
            name: "email_send",
            description: "Send a new email message",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "to": Schema.array("Recipients", items: Schema.object(
                        properties: [
                            "email": Schema.string("Email address"),
                            "name": Schema.string("Display name"),
                        ],
                        required: ["email"]
                    )),
                    "subject": Schema.string("Email subject"),
                    "body": Schema.string("Plain text body"),
                    "bodyHtml": Schema.string("HTML body (optional)"),
                    "cc": Schema.array("CC recipients", items: Schema.object(
                        properties: [
                            "email": Schema.string("Email address"),
                            "name": Schema.string("Display name"),
                        ],
                        required: ["email"]
                    )),
                    "bcc": Schema.array("BCC recipients", items: Schema.object(
                        properties: [
                            "email": Schema.string("Email address"),
                            "name": Schema.string("Display name"),
                        ],
                        required: ["email"]
                    )),
                ],
                required: ["account", "to", "subject", "body"]
            ),
            ipcMethod: "email.send"
        ),
        MCPToolDefinition(
            name: "email_reply",
            description: "Reply to an existing email message",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "originalMessageId": Schema.string("ID of the message to reply to"),
                    "body": Schema.string("Reply body text"),
                    "replyAll": Schema.boolean("Reply to all recipients (default: false)"),
                ],
                required: ["account", "originalMessageId", "body"]
            ),
            ipcMethod: "email.reply"
        ),
        MCPToolDefinition(
            name: "email_forward",
            description: "Forward an email message to new recipients",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "originalMessageId": Schema.string("ID of the message to forward"),
                    "to": Schema.array("Forward recipients", items: Schema.object(
                        properties: [
                            "email": Schema.string("Email address"),
                            "name": Schema.string("Display name"),
                        ],
                        required: ["email"]
                    )),
                    "body": Schema.string("Additional body text to prepend"),
                ],
                required: ["account", "originalMessageId", "to"]
            ),
            ipcMethod: "email.forward"
        ),
        MCPToolDefinition(
            name: "email_move",
            description: "Move an email message to a different folder",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Message ID"),
                    "folder": Schema.string("Destination folder path"),
                ],
                required: ["account", "id", "folder"]
            ),
            ipcMethod: "email.move"
        ),
        MCPToolDefinition(
            name: "email_delete",
            description: "Delete an email message",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Message ID"),
                    "permanent": Schema.boolean("Permanently delete instead of moving to trash (default: false)"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "email.delete"
        ),
        MCPToolDefinition(
            name: "email_update_flags",
            description: "Update flags on an email message (read, starred, etc.)",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Message ID"),
                    "add": Schema.array("Flags to add", items: Schema.string("Flag name")),
                    "remove": Schema.array("Flags to remove", items: Schema.string("Flag name")),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "email.updateFlags"
        ),
        MCPToolDefinition(
            name: "email_search",
            description: "Search email messages by query string",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "query": Schema.string("Search query"),
                    "folder": Schema.string("Folder to search in (optional, searches all if omitted)"),
                    "limit": Schema.integer("Maximum number of results"),
                    "offset": Schema.integer("Offset for pagination"),
                ],
                required: ["account", "query"]
            ),
            ipcMethod: "email.search"
        ),
        MCPToolDefinition(
            name: "email_list_folders",
            description: "List all email folders for an account",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                ],
                required: ["account"]
            ),
            ipcMethod: "email.listFolders"
        ),
        MCPToolDefinition(
            name: "email_create_folder",
            description: "Create a new email folder",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "name": Schema.string("Folder name"),
                    "parent": Schema.string("Parent folder path (optional)"),
                ],
                required: ["account", "name"]
            ),
            ipcMethod: "email.createFolder"
        ),
        MCPToolDefinition(
            name: "email_delete_folder",
            description: "Delete an email folder",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "path": Schema.string("Folder path to delete"),
                ],
                required: ["account", "path"]
            ),
            ipcMethod: "email.deleteFolder"
        ),
        MCPToolDefinition(
            name: "email_download_attachment",
            description: "Download an email attachment to a local file",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "messageId": Schema.string("Message ID containing the attachment"),
                    "filename": Schema.string("Attachment filename"),
                    "path": Schema.string("Local file path to save the attachment"),
                ],
                required: ["account", "messageId", "filename", "path"]
            ),
            ipcMethod: "email.downloadAttachment"
        ),
    ]

    // MARK: - Calendar Tools

    static let calendarTools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "calendar_list_calendars",
            description: "List all calendars for an account",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                ],
                required: ["account"]
            ),
            ipcMethod: "calendar.listCalendars"
        ),
        MCPToolDefinition(
            name: "calendar_list_events",
            description: "List calendar events within a date range",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "from": Schema.string("Start date/time (ISO 8601)"),
                    "to": Schema.string("End date/time (ISO 8601)"),
                    "calendar": Schema.string("Calendar name (optional, lists all if omitted)"),
                ],
                required: ["account", "from", "to"]
            ),
            ipcMethod: "calendar.listEvents"
        ),
        MCPToolDefinition(
            name: "calendar_create_event",
            description: "Create a new calendar event",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "calendar": Schema.string("Calendar name"),
                    "title": Schema.string("Event title"),
                    "start": Schema.string("Start date/time (ISO 8601)"),
                    "end": Schema.string("End date/time (ISO 8601)"),
                    "location": Schema.string("Event location"),
                    "description": Schema.string("Event description"),
                    "attendees": Schema.array("Attendee email addresses", items: Schema.string("Email address")),
                    "recurrence": Schema.string("Recurrence rule (RFC 5545 RRULE)"),
                    "reminders": Schema.array("Reminder minutes before event", items: Schema.integer("Minutes")),
                    "allDay": Schema.boolean("All-day event (default: false)"),
                ],
                required: ["account", "calendar", "title", "start", "end"]
            ),
            ipcMethod: "calendar.createEvent"
        ),
        MCPToolDefinition(
            name: "calendar_update_event",
            description: "Update an existing calendar event",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Event ID"),
                    "title": Schema.string("Updated title"),
                    "start": Schema.string("Updated start date/time (ISO 8601)"),
                    "end": Schema.string("Updated end date/time (ISO 8601)"),
                    "location": Schema.string("Updated location"),
                    "description": Schema.string("Updated description"),
                    "attendees": Schema.array("Updated attendees", items: Schema.string("Email address")),
                    "recurrence": Schema.string("Updated recurrence rule"),
                    "reminders": Schema.array("Updated reminders", items: Schema.integer("Minutes")),
                    "allDay": Schema.boolean("Updated all-day flag"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "calendar.updateEvent"
        ),
        MCPToolDefinition(
            name: "calendar_delete_event",
            description: "Delete a calendar event",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Event ID"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "calendar.deleteEvent"
        ),
    ]

    // MARK: - Contacts Tools

    static let contactsTools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "contacts_list_address_books",
            description: "List all address books for an account",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                ],
                required: ["account"]
            ),
            ipcMethod: "contacts.listAddressBooks"
        ),
        MCPToolDefinition(
            name: "contacts_list",
            description: "List or search contacts in an address book",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "addressBook": Schema.string("Address book name (optional)"),
                    "query": Schema.string("Search query (optional)"),
                    "limit": Schema.integer("Maximum number of results"),
                    "offset": Schema.integer("Offset for pagination"),
                ],
                required: ["account"]
            ),
            ipcMethod: "contacts.list"
        ),
        MCPToolDefinition(
            name: "contacts_create",
            description: "Create a new contact",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "addressBook": Schema.string("Address book name"),
                    "displayName": Schema.string("Display name"),
                    "firstName": Schema.string("First name"),
                    "lastName": Schema.string("Last name"),
                    "emails": Schema.array("Email addresses", items: Schema.object(
                        properties: [
                            "type": Schema.string("Type (home, work, other)"),
                            "value": Schema.string("Email address"),
                        ],
                        required: ["value"]
                    )),
                    "phones": Schema.array("Phone numbers", items: Schema.object(
                        properties: [
                            "type": Schema.string("Type (home, work, mobile, other)"),
                            "value": Schema.string("Phone number"),
                        ],
                        required: ["value"]
                    )),
                    "organization": Schema.string("Organization/company name"),
                    "title": Schema.string("Job title"),
                    "note": Schema.string("Notes"),
                ],
                required: ["account", "addressBook", "displayName"]
            ),
            ipcMethod: "contacts.create"
        ),
        MCPToolDefinition(
            name: "contacts_update",
            description: "Update an existing contact",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Contact ID"),
                    "displayName": Schema.string("Updated display name"),
                    "firstName": Schema.string("Updated first name"),
                    "lastName": Schema.string("Updated last name"),
                    "emails": Schema.array("Updated email addresses", items: Schema.object(
                        properties: [
                            "type": Schema.string("Type (home, work, other)"),
                            "value": Schema.string("Email address"),
                        ],
                        required: ["value"]
                    )),
                    "phones": Schema.array("Updated phone numbers", items: Schema.object(
                        properties: [
                            "type": Schema.string("Type (home, work, mobile, other)"),
                            "value": Schema.string("Phone number"),
                        ],
                        required: ["value"]
                    )),
                    "organization": Schema.string("Updated organization"),
                    "title": Schema.string("Updated job title"),
                    "note": Schema.string("Updated notes"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "contacts.update"
        ),
        MCPToolDefinition(
            name: "contacts_delete",
            description: "Delete a contact",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Contact ID"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "contacts.delete"
        ),
    ]

    // MARK: - Tasks Tools

    static let tasksTools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "tasks_list_task_lists",
            description: "List all task lists for an account",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                ],
                required: ["account"]
            ),
            ipcMethod: "tasks.listTaskLists"
        ),
        MCPToolDefinition(
            name: "tasks_list",
            description: "List tasks in a task list",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "taskList": Schema.string("Task list name (optional)"),
                    "includeCompleted": Schema.boolean("Include completed tasks (default: false)"),
                ],
                required: ["account"]
            ),
            ipcMethod: "tasks.list"
        ),
        MCPToolDefinition(
            name: "tasks_create",
            description: "Create a new task",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "taskList": Schema.string("Task list name"),
                    "title": Schema.string("Task title"),
                    "description": Schema.string("Task description"),
                    "due": Schema.string("Due date (ISO 8601)"),
                    "priority": Schema.integer("Priority (1=high, 5=low)"),
                ],
                required: ["account", "taskList", "title"]
            ),
            ipcMethod: "tasks.create"
        ),
        MCPToolDefinition(
            name: "tasks_update",
            description: "Update an existing task",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Task ID"),
                    "title": Schema.string("Updated title"),
                    "description": Schema.string("Updated description"),
                    "due": Schema.string("Updated due date (ISO 8601)"),
                    "priority": Schema.integer("Updated priority"),
                    "completed": Schema.boolean("Mark as completed"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "tasks.update"
        ),
        MCPToolDefinition(
            name: "tasks_delete",
            description: "Delete a task",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "id": Schema.string("Task ID"),
                ],
                required: ["account", "id"]
            ),
            ipcMethod: "tasks.delete"
        ),
    ]

    // MARK: - Admin Tools

    static let adminTools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "audit_list",
            description: "List audit log entries",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label (optional, filter by account)"),
                    "limit": Schema.integer("Maximum number of entries to return"),
                ]
            ),
            ipcMethod: "audit.list"
        ),
        MCPToolDefinition(
            name: "accounts_list",
            description: "List all configured email accounts",
            inputSchema: Schema.object(properties: [:]),
            ipcMethod: "accounts.list"
        ),
        MCPToolDefinition(
            name: "status",
            description: "Get ClawMail daemon status including account connection states",
            inputSchema: Schema.object(properties: [:]),
            ipcMethod: "status"
        ),
        MCPToolDefinition(
            name: "recipients_list",
            description: "List approved and pending recipients",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label (optional)"),
                ]
            ),
            ipcMethod: "recipients.list"
        ),
        MCPToolDefinition(
            name: "recipients_approve",
            description: "Approve one or more recipients for sending",
            inputSchema: Schema.object(
                properties: [
                    "account": Schema.string("Account label"),
                    "emails": Schema.array("Email addresses to approve", items: Schema.string("Email address")),
                    "email": Schema.string("Single email address to approve (alternative to emails)"),
                ],
                required: ["account"]
            ),
            ipcMethod: "recipients.approve"
        ),
        MCPToolDefinition(
            name: "recipients_remove",
            description: "Remove a recipient from the approved list",
            inputSchema: Schema.object(
                properties: [
                    "email": Schema.string("Email address to remove"),
                ],
                required: ["email"]
            ),
            ipcMethod: "recipients.remove"
        ),
    ]
}
