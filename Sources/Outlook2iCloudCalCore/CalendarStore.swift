import Foundation

/// The fields copied from an Outlook event to the iCloud calendar.
public struct EventFields: Equatable, Sendable {
    public let title: String
    /// Nil when the location is empty, so Outlook's "" and EventKit's nil compare equal.
    public let location: String?
    public let start: Date
    public let end: Date

    public init(title: String, location: String?, start: Date, end: Date) {
        self.title = title
        self.location = location?.isEmpty == true ? nil : location
        self.start = start
        self.end = end
    }

    public init(_ event: OutlookEvent) {
        self.init(
            title: event.subject, location: event.location, start: event.start, end: event.end)
    }
}

/// An event read back from the calendar store.
public struct StoredEvent: Equatable, Sendable {
    /// The store's identifier for the event (`EKEvent.calendarItemIdentifier`).
    public let storeID: String
    /// Nil when the event was not created by this app.
    public let meetingId: String?
    public let fields: EventFields

    public init(storeID: String, meetingId: String?, fields: EventFields) {
        self.storeID = storeID
        self.meetingId = meetingId
        self.fields = fields
    }
}

/// The destination calendar that events are mirrored into.
public protocol CalendarStore: Sendable {
    func events(in range: DateInterval) async throws -> [StoredEvent]
    func add(meetingId: String, fields: EventFields) async throws
    func update(storeID: String, fields: EventFields) async throws
    func delete(storeID: String) async throws
    func commit() async throws
    /// Discards all staged changes that have not been committed.
    func rollback() async
}
