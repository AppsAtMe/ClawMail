import Foundation
import SwiftSoup

public struct EmailCleaner: Sendable {
    public init() {}

    /// Clean plain text email body: strip signatures, quoted replies, collapse whitespace
    public func clean(plainText: String) -> String {
        var lines = plainText.components(separatedBy: "\n")

        // Strip email signature (-- delimiter)
        if let sigIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "--" }) {
            lines = Array(lines[..<sigIndex])
        }

        // Also detect common signature patterns without -- delimiter
        let sigPatterns = [
            "Sent from my iPhone",
            "Sent from my iPad",
            "Sent from Mail for",
            "Get Outlook for",
            "Envoyé de mon",
            "Von meinem iPhone",
        ]
        for pattern in sigPatterns {
            if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(pattern) }) {
                lines = Array(lines[..<idx])
                break
            }
        }

        // Remove quoted reply blocks (lines starting with >)
        lines = lines.filter { !$0.hasPrefix(">") }

        // Remove "On ... wrote:" lines that precede quotes
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let wrotePattern = trimmed.hasSuffix("wrote:") || trimmed.hasSuffix("wrote :")
            let onPattern = trimmed.hasPrefix("On ") && wrotePattern
            return !onPattern
        }

        var result = lines.joined(separator: "\n")

        // Collapse 3+ newlines into 2
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Trim leading/trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Extract plain text from HTML email body
    public func extractPlainTextFromHTML(_ html: String) -> String {
        do {
            let doc = try SwiftSoup.parse(html)

            // Remove style and script tags entirely
            try doc.select("style").remove()
            try doc.select("script").remove()

            // Convert links: <a href="url">text</a> -> text (url)
            for link in try doc.select("a[href]") {
                let href = try link.attr("href")
                let text = try link.text()
                if !href.isEmpty && href != text {
                    try link.text("\(text) (\(href))")
                }
            }

            // Convert <br> to newlines
            for br in try doc.select("br") {
                try br.before("\n")
            }

            // Convert block elements to newlines
            for tag in ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "tr"] {
                for element in try doc.select(tag) {
                    try element.before("\n")
                    try element.after("\n")
                }
            }

            var text = try doc.text()

            // Collapse excessive newlines
            while text.contains("\n\n\n") {
                text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            }

            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // If parsing fails, strip tags manually
            return html
                .replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
