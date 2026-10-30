import Foundation
import Testing

@testable import Outlook2iCloudCalCore

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct CalendarViewParserTests {
    @Test func parsesEventsInsideBoundaryMarkers() throws {
        let events = try CalendarViewParser.parse(fixture("calendar_view.txt"))
        #expect(events.count == 4)
        #expect(events[0].subject == "Team sync")
        #expect(events[0].start == ISO8601DateFormatter().date(from: "2026-10-30T09:00:00+09:00"))
        #expect(events[0].response == "Accept")
        #expect(events[1].subject == "Declined: Demo")
        #expect(events[2].isAllDay)
        #expect(events[3].location == "")
        #expect(events[3].response == "Organizer")
    }

    @Test func parsesBareArray() throws {
        #expect(try CalendarViewParser.parse("[]") == [])
    }

    @Test func rejectsOutputWithoutArray() {
        #expect(throws: ParseError.noJSONArray) {
            try CalendarViewParser.parse("[mcporter] MCP error -32602")
        }
    }

    @Test func rejectsErrorOutputContainingJSONLikeBrackets() {
        let output = "[mcporter] MCP error -32602: invalid\n[\n  {\n    \"received\": \"x\"\n  }\n]"
        #expect(throws: ParseError.noJSONArray) { try CalendarViewParser.parse(output) }
    }

    @Test func rejectsPartialOrMalformedJSON() {
        do {
            _ = try CalendarViewParser.parse("[{\"meetingId\": \"a\"}]")
            Issue.record("expected invalidJSON")
        } catch ParseError.invalidJSON {
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func rejectsArraysEmbeddedMidLine() {
        let outputs = [
            "[mcporter] MCP error -32602: received [] expected array",
            "[mcporter] MCP error: got [{\"a\":1}] then more text]",
        ]
        for output in outputs {
            #expect(throws: ParseError.noJSONArray) { try CalendarViewParser.parse(output) }
        }
    }

    @Test func defaultsNullOrMissingLocationToEmpty() throws {
        let base = """
            "meetingId":"a","subject":"s","start":"2026-10-30T09:00:00+09:00",\
            "end":"2026-10-30T10:00:00+09:00","isCanceled":false,"isAllDay":false,"response":"Accept"
            """
        let nullLocation = try CalendarViewParser.parse("[{\(base),\"location\":null}]")
        let missingLocation = try CalendarViewParser.parse("[{\(base)}]")
        #expect(nullLocation.map { $0.location } == [""])
        #expect(missingLocation.map { $0.location } == [""])
    }

    @Test func rejectsInvalidDate() {
        let json = """
            [{"meetingId":"a","subject":"s","start":"not-a-date","end":"2026-10-30T10:00:00+09:00",\
            "location":"","isCanceled":false,"isAllDay":false,"response":"Accept"}]
            """
        #expect(throws: ParseError.invalidDate("not-a-date")) { try CalendarViewParser.parse(json) }
    }

    @Test func ignoresUnknownFieldsAndRecurrenceSeriesId() throws {
        let json = """
            [{"meetingId":"a","subject":"s","start":"2026-10-30T09:00:00+09:00",\
            "end":"2026-10-30T10:00:00+09:00","location":"L","isCanceled":false,"isAllDay":false,\
            "response":"Accept","isRecurring":true,"seriesId":"x","extra":{"k":1}}]
            """
        let events = try CalendarViewParser.parse(json)
        #expect(events.map { $0.meetingId } == ["a"])
    }
}
