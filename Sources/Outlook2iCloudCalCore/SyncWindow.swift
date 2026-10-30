import Foundation

/// The span of time to mirror, split into seven month-long buckets.
public struct SyncWindow: Equatable, Sendable {
    /// From 0:00 one month before today to 0:00 six months after today.
    public let range: DateInterval
    /// Seven consecutive half-open month intervals that exactly cover `range`.
    public let buckets: [DateInterval]

    public init(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        // Every boundary is added to `today` directly so that month-end clamping
        // never accumulates from one boundary to the next.
        let boundaries = (-1...6).map { offset in
            calendar.date(byAdding: .month, value: offset, to: today)!
        }
        self.range = DateInterval(start: boundaries[0], end: boundaries[7])
        self.buckets = (0..<7).map { index in
            DateInterval(start: boundaries[index], end: boundaries[index + 1])
        }
    }

    /// Whether an event overlapping `[start, end)` belongs to the window.
    public func contains(start: Date, end: Date) -> Bool {
        end > range.start && start < range.end
    }

    /// The bucket holding `start`; a start before the range clamps to 0 and a
    /// start at or after the range end yields nil.
    public func bucketIndex(start: Date) -> Int? {
        if start >= range.end { return nil }
        if start < range.start { return 0 }
        return buckets.firstIndex { start >= $0.start && start < $0.end }
    }

    /// Per-bucket counts of events inside the window, regardless of eligibility.
    public func bucketCounts(_ events: [OutlookEvent]) -> [Int] {
        var counts = [Int](repeating: 0, count: buckets.count)
        for event in events where contains(start: event.start, end: event.end) {
            if let index = bucketIndex(start: event.start) {
                counts[index] += 1
            }
        }
        return counts
    }
}
