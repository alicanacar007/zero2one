import Foundation
import AppKit

enum LogLevel: String, Codable {
    case info
    case error
}

struct LogEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let timestamp: Date
    let service: String
    let level: LogLevel
    let message: String
    let url: String?
    let statusCode: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        service: String,
        level: LogLevel,
        message: String,
        url: String? = nil,
        statusCode: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.service = service
        self.level = level
        self.message = message
        self.url = url
        self.statusCode = statusCode
    }
}

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    func log(
        _ level: LogLevel,
        service: String,
        message: String,
        url: URL? = nil,
        statusCode: Int? = nil
    ) {
        let entry = LogEntry(
            service: service,
            level: level,
            message: message,
            url: url?.absoluteString,
            statusCode: statusCode
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func copyErrorsToPasteboard() {
        let errors = entries.filter { $0.level == .error }
        let payload = LogStore.format(entries: errors)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
    }

    func copyAllToPasteboard() {
        let payload = LogStore.format(entries: entries)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
    }

    static func format(entries: [LogEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            var parts: [String] = []
            parts.append("[\(formatter.string(from: entry.timestamp))]")
            parts.append("[\(entry.service)]")
            parts.append("[\(entry.level.rawValue.uppercased())]")
            if let status = entry.statusCode {
                parts.append("[\(status)]")
            }
            if let url = entry.url {
                parts.append(url)
            }
            parts.append(entry.message)
            return parts.joined(separator: " ")
        }.joined(separator: "\n")
    }
}
