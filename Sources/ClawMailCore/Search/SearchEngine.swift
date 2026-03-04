import Foundation

// MARK: - SearchQuery

public struct SearchQuery: Sendable {
    public var from: String?
    public var to: String?
    public var subject: String?
    public var body: String?
    public var hasAttachment: Bool?
    public var isUnread: Bool?
    public var isRead: Bool?
    public var isFlagged: Bool?
    public var before: Date?
    public var after: Date?
    public var folder: String?
    public var freeText: String?

    public init() {}

    /// Build an FTS5 query string for SQLite search.
    ///
    /// NOTE: This produces FTS5 queries with column prefixes and operators (AND, OR).
    /// Each individual term is phrase-escaped via `ftsEscape()`, but the overall query
    /// structure uses raw FTS5 syntax. This is intentional — `MetadataIndex.sanitizeFTS5Query()`
    /// is NOT applied to these queries since they are constructed internally with controlled structure.
    /// `sanitizeFTS5Query()` is only for raw user input that bypasses SearchEngine (e.g., direct
    /// FTS5 query strings from the REST API search endpoint).
    public var ftsQuery: String? {
        var parts: [String] = []

        if let subject = subject {
            parts.append("subject:\(ftsEscape(subject))")
        }
        if let from = from {
            parts.append("sender_email:\(ftsEscape(from)) OR sender_name:\(ftsEscape(from))")
        }
        if let body = body {
            parts.append("body_text:\(ftsEscape(body))")
        }
        if let freeText = freeText {
            parts.append(ftsEscape(freeText))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " AND ")
    }

    private func ftsEscape(_ text: String) -> String {
        // Quote the term for FTS5 to handle special characters
        let cleaned = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(cleaned)\""
    }
}

// MARK: - SearchEngine

public struct SearchEngine: Sendable {
    public init() {}

    /// Parse a query string into a structured SearchQuery
    public func parseQuery(_ query: String) -> SearchQuery {
        var result = SearchQuery()
        var freeTextParts: [String] = []

        // Tokenize respecting quoted strings
        let tokens = tokenize(query)

        for token in tokens {
            if let colonIndex = token.firstIndex(of: ":") {
                let prefix = String(token[token.startIndex..<colonIndex]).lowercased()
                let value = String(token[token.index(after: colonIndex)...])

                switch prefix {
                case "from":
                    result.from = value
                case "to":
                    result.to = value
                case "subject":
                    result.subject = value
                case "body":
                    result.body = value
                case "has" where value.lowercased() == "attachment":
                    result.hasAttachment = true
                case "is":
                    switch value.lowercased() {
                    case "unread": result.isUnread = true
                    case "read": result.isRead = true
                    case "flagged": result.isFlagged = true
                    default: freeTextParts.append(token)
                    }
                case "before":
                    result.before = parseDate(value)
                case "after":
                    result.after = parseDate(value)
                case "in":
                    result.folder = value
                default:
                    freeTextParts.append(token)
                }
            } else {
                freeTextParts.append(token)
            }
        }

        if !freeTextParts.isEmpty {
            result.freeText = freeTextParts.joined(separator: " ")
        }

        return result
    }

    // MARK: - Tokenizer

    private func tokenize(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        for char in query {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == " " && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    // MARK: - Date Parser

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try ISO 8601 date only
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: string) {
            return date
        }

        // Try ISO 8601 with time
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: string) {
            return date
        }

        return nil
    }
}
