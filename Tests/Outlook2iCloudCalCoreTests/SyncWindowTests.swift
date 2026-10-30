import Foundation
import Testing

@testable import Outlook2iCloudCalCore

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

    @Test func monthEndClampingKeepsBucketsContiguous() {
        let w = SyncWindow(now: tokyo("2027-03-31T10:00:00"), calendar: cal)
        #expect(w.range.start == tokyo("2027-02-28T00:00:00"))
        #expect(w.range.end == tokyo("2027-09-30T00:00:00"))
        expectContiguous(w)
    }

    @Test func leapDayKeepsBucketsContiguous() {
        let w = SyncWindow(now: tokyo("2028-02-29T10:00:00"), calendar: cal)
        expectContiguous(w)
    }

    private func expectContiguous(_ w: SyncWindow) {
        #expect(w.buckets.count == 7)
        #expect(w.buckets[0].start == w.range.start)
        #expect(w.buckets[6].end == w.range.end)
        for i in 0..<6 {
            #expect(w.buckets[i].end == w.buckets[i + 1].start)
        }
    }
}
