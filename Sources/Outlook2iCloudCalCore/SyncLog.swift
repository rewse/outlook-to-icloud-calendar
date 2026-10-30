import Foundation

/// A plain-text log with one file per local day, named `YYYY-MM-DD.log`.
public final class SyncLog: @unchecked Sendable {
    public let directory: URL
    private let retentionDays: Int
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        directory: URL, retentionDays: Int = 14, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.retentionDays = retentionDays
        self.now = now
    }

    /// Appends "<ISO 8601 local time> <message>" to today's file, with line
    /// breaks in `message` escaped as `\n` and `\r` so that each entry stays on
    /// one line. Failures are ignored so that logging never interrupts a sync.
    public func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let date = now()
        let calendar = Self.localCalendar()
        let timestamp = ISO8601DateFormatter.string(
            from: date, timeZone: calendar.timeZone, formatOptions: .withInternetDateTime)
        let line = message.replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let data = Data("\(timestamp) \(line)\n".utf8)
        let day = Self.dayFormatter(calendar).string(from: date)
        let file = directory.appendingPathComponent("\(day).log")
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !manager.fileExists(atPath: file.path) {
                try data.write(to: file)
                return
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Logging is best effort.
        }
    }

    /// Deletes `YYYY-MM-DD.log` files dated more than `retentionDays` days
    /// before today. Other files are left alone.
    public func purge() {
        lock.lock()
        defer { lock.unlock() }
        let calendar = Self.localCalendar()
        guard
            let cutoff = calendar.date(
                byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: now())),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        let formatter = Self.dayFormatter(calendar)
        for name in names where name.hasSuffix(".log") {
            let stem = String(name.dropLast(4))
            // Round-tripping rejects names that merely parse leniently.
            guard let day = formatter.date(from: stem), formatter.string(from: day) == stem,
                day < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func localCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

/// Formats sync log lines in the time zone of `calendar`.
struct SyncLogFormat {
    private let minute: DateFormatter
    private let time: DateFormatter
    private let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
        func formatter(_ format: String) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
        self.minute = formatter("yyyy-MM-dd HH:mm")
        self.time = formatter("HH:mm")
    }

    /// "2026-11-05 13:00-13:30" within a day, otherwise both ends in full.
    func span(_ start: Date, _ end: Date) -> String {
        let endText =
            calendar.isDate(start, inSameDayAs: end)
            ? time.string(from: end) : minute.string(from: end)
        return "\(minute.string(from: start))-\(endText)"
    }

    func span(_ interval: DateInterval) -> String {
        span(interval.start, interval.end)
    }

    /// `verb "title" start-end`.
    func event(_ verb: String, _ fields: EventFields) -> String {
        "\(verb) \"\(fields.title)\" \(span(fields.start, fields.end))"
    }

    /// Counts per exclusion reason, with unknown responses sorted by value.
    func exclusions(_ counts: [ExclusionReason: Int]) -> String {
        let responses = counts.compactMap { reason, count -> (String, Int)? in
            if case .response(let value) = reason { return (value, count) }
            return nil
        }.sorted { $0.0 < $1.0 }
        let fixed = [
            "canceled=\(counts[.canceled, default: 0])",
            "declined=\(counts[.declined, default: 0])",
            "allDay=\(counts[.allDay, default: 0])",
        ]
        return (["excluded"] + fixed + responses.map { "response(\($0.0))=\($0.1)" })
            .joined(separator: " ")
    }

    func counts(_ counts: SyncCounts) -> String {
        "added=\(counts.added) updated=\(counts.updated) deleted=\(counts.deleted)"
            + " held=\(counts.held)"
    }
}
