import Foundation
import Testing

@testable import Outlook2iCloudCalCore

let cal: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

func tokyo(_ local: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = cal
    formatter.timeZone = cal.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.date(from: local)!
}

func event(
    id: String = "id-1",
    response: String = "Accept",
    subject: String = "Sample",
    start: String = "2026-11-02T10:00:00",
    end: String = "2026-11-02T11:00:00",
    isAllDay: Bool = false,
    isCanceled: Bool = false
) -> OutlookEvent {
    OutlookEvent(
        meetingId: id,
        subject: subject,
        start: tokyo(start),
        end: tokyo(end),
        location: "",
        isAllDay: isAllDay,
        isCanceled: isCanceled,
        response: response)
}

struct SyncWindowTests {
    let now = tokyo("2026-10-30T15:12:00")

    @Test func windowFor20261030() {
        let w = SyncWindow(now: now, calendar: cal)
        #expect(w.range.start == tokyo("2026-09-30T00:00:00"))
        #expect(w.range.end == tokyo("2027-04-30T00:00:00"))
        #expect(w.buckets.count == 7)
        #expect(w.buckets[0].start == w.range.start)
        #expect(w.buckets[6].start == tokyo("2027-03-30T00:00:00"))
        #expect(w.buckets[6].end == w.range.end)
        for i in 1..<7 {
            #expect(w.buckets[i].start == w.buckets[i - 1].end)
        }
    }

    @Test func eventStraddlingRangeStartIsInBucketZero() {
        let w = SyncWindow(now: now, calendar: cal)
        #expect(w.contains(start: tokyo("2026-09-29T23:00:00"), end: tokyo("2026-09-30T01:00:00")))
        #expect(w.bucketIndex(start: tokyo("2026-09-29T23:00:00")) == 0)
        #expect(!w.contains(start: tokyo("2026-09-29T09:00:00"), end: tokyo("2026-09-30T00:00:00")))
    }

    @Test func bucketIndexBoundaries() {
        let w = SyncWindow(now: now, calendar: cal)
        #expect(w.bucketIndex(start: tokyo("2026-09-30T00:00:00")) == 0)
        #expect(w.bucketIndex(start: tokyo("2026-10-29T23:59:59")) == 0)
        #expect(w.bucketIndex(start: tokyo("2026-10-30T00:00:00")) == 1)
        #expect(w.bucketIndex(start: tokyo("2027-04-29T23:59:59")) == 6)
        #expect(w.bucketIndex(start: tokyo("2027-04-30T00:00:00")) == nil)
        #expect(!w.contains(start: tokyo("2027-04-30T00:00:00"), end: tokyo("2027-04-30T01:00:00")))
    }

    @Test func bucketCountsIncludeExcludedEvents() {
        let w = SyncWindow(now: now, calendar: cal)
        let events = [
            event(id: "a", start: "2026-10-05T10:00:00", end: "2026-10-05T11:00:00"),
            event(id: "b", response: "Decline", start: "2026-10-06T10:00:00", end: "2026-10-06T11:00:00"),
            event(id: "c", start: "2026-11-15T10:00:00", end: "2026-11-15T11:00:00"),
            event(id: "d", start: "2027-04-10T10:00:00", end: "2027-04-10T11:00:00"),
            event(id: "e", start: "2026-08-01T10:00:00", end: "2026-08-01T11:00:00"),
            event(id: "f", start: "2027-06-01T10:00:00", end: "2027-06-01T11:00:00"),
        ]
        #expect(w.bucketCounts(events) == [2, 1, 0, 0, 0, 0, 1])
    }
}
