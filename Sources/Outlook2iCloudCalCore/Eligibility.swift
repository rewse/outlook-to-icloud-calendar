import Foundation

/// Why an Outlook event is not copied to iCloud.
public enum ExclusionReason: Hashable, Sendable {
    case declined
    case canceled
    case allDay
    /// A response other than Accept or Organizer, carrying the raw value.
    case response(String)
}

public enum Eligibility {
    private static let copiedResponses: Set<String> = ["Accept", "Organizer"]

    /// Returns nil when the event should be copied. When several reasons apply,
    /// the first of canceled, declined, all-day, response is returned.
    public static func evaluate(_ event: OutlookEvent) -> ExclusionReason? {
        if event.isCanceled || event.subject.hasPrefix("Canceled:") { return .canceled }
        if event.subject.hasPrefix("Declined:") { return .declined }
        if event.isAllDay { return .allDay }
        if !copiedResponses.contains(event.response) { return .response(event.response) }
        return nil
    }
}

/// Drops later events that repeat a `meetingId`, keeping the first occurrence
/// and the original order.
public func dedupeByMeetingId(_ events: [OutlookEvent]) -> [OutlookEvent] {
    var seen = Set<String>()
    return events.filter { seen.insert($0.meetingId).inserted }
}
