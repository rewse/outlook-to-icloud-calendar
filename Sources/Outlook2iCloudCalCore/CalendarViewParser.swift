import Foundation

public enum ParseError: Error, Equatable {
    case noJSONArray
    case invalidJSON(String)
    case invalidDate(String)
}

/// Parses the text printed by `mcporter call ... calendar_view`.
public enum CalendarViewParser {
    private struct RawEvent: Decodable {
        let meetingId: String
        let subject: String
        let start: String
        let end: String
        let location: String
        let isAllDay: Bool
        let isCanceled: Bool
        let response: String

        private enum CodingKeys: String, CodingKey {
            case meetingId, subject, start, end, location, isAllDay, isCanceled, response
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            meetingId = try c.decode(String.self, forKey: .meetingId)
            subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
            start = try c.decode(String.self, forKey: .start)
            end = try c.decode(String.self, forKey: .end)
            location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
            isAllDay = try c.decode(Bool.self, forKey: .isAllDay)
            isCanceled = try c.decode(Bool.self, forKey: .isCanceled)
            // An empty response is an unrecognized one, which Eligibility excludes.
            response = try c.decodeIfPresent(String.self, forKey: .response) ?? ""
        }
    }

    /// Returns every event in `output`, or throws; never returns a partial list.
    public static func parse(_ output: String) throws -> [OutlookEvent] {
        guard let json = extractArray(output) else { throw ParseError.noJSONArray }
        let raw: [RawEvent]
        do {
            raw = try JSONDecoder().decode([RawEvent].self, from: Data(json.utf8))
        } catch {
            throw ParseError.invalidJSON(String(describing: error))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        func date(_ text: String) throws -> Date {
            guard let value = formatter.date(from: text) else { throw ParseError.invalidDate(text) }
            return value
        }
        return try raw.map {
            OutlookEvent(
                meetingId: $0.meetingId,
                subject: $0.subject,
                start: try date($0.start),
                end: try date($0.end),
                location: $0.location,
                isAllDay: $0.isAllDay,
                isCanceled: $0.isCanceled,
                response: $0.response)
        }
    }

    /// Finds the line that is itself a JSON array (starts with `[{` or `[]` and ends with `]`).
    /// Boundary markers, notices, and error text are skipped; an array embedded mid-line
    /// is never accepted.
    private static func extractArray(_ output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if (trimmed.hasPrefix("[{") || trimmed.hasPrefix("[]")) && trimmed.hasSuffix("]") {
                return trimmed
            }
        }
        return nil
    }
}
