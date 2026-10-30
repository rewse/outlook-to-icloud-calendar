import EventKit
import Foundation
import Outlook2iCloudCalCore

enum EventKitStoreError: Error {
    case accessDenied
    case eventNotFound(storeID: String)
    case iCloudSourceNotFound
}

/// A `CalendarStore` backed by the "Business" calendar of the iCloud account.
///
/// Only events in that calendar are read or written. Changes are staged in the `EKEventStore`
/// until `commit()`, and `rollback()` discards them.
///
/// `@unchecked Sendable` is safe because every access to `eventStore` and `cachedCalendar` goes
/// through `lock`, and no `EKEvent` or `EKCalendar` escapes the lock: callers only receive value
/// types. No lock is held across an `await`.
final class EventKitStore: CalendarStore, @unchecked Sendable {
    static let calendarTitle = "Business"

    private let eventStore: EKEventStore
    private let lock = NSLock()
    private var cachedCalendar: EKCalendar?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func requestAccess() async throws {
        guard try await eventStore.requestFullAccessToEvents() else {
            throw EventKitStoreError.accessDenied
        }
    }

    func events(in range: DateInterval) async throws -> [StoredEvent] {
        try lock.withLock {
            let calendar = try businessCalendar()
            let predicate = eventStore.predicateForEvents(
                withStart: range.start, end: range.end, calendars: [calendar])
            // Recurring events are skipped: this app never creates them, and all occurrences
            // share one `calendarItemIdentifier`, so deleting by that ID could remove an
            // occurrence outside the window. They are never managed, deleted, or counted.
            let events = eventStore.events(matching: predicate).filter { !$0.hasRecurrenceRules }
            return events.map { event in
                StoredEvent(
                    storeID: event.calendarItemIdentifier,
                    meetingId: EventURL.meetingId(from: event.url),
                    fields: EventFields(
                        title: event.title ?? "", location: event.location,
                        start: event.startDate, end: event.endDate))
            }
        }
    }

    func add(meetingId: String, fields: EventFields) async throws {
        try lock.withLock {
            let event = EKEvent(eventStore: eventStore)
            event.calendar = try businessCalendar()
            event.url = EventURL.make(meetingId: meetingId)
            event.timeZone = .current
            apply(fields, to: event)
            try eventStore.save(event, span: .thisEvent, commit: false)
        }
    }

    func update(storeID: String, fields: EventFields) async throws {
        try lock.withLock {
            guard let event = try existingEvent(storeID: storeID) else {
                throw EventKitStoreError.eventNotFound(storeID: storeID)
            }
            apply(fields, to: event)
            try eventStore.save(event, span: .thisEvent, commit: false)
        }
    }

    func delete(storeID: String) async throws {
        try lock.withLock {
            guard let event = try existingEvent(storeID: storeID) else { return }
            try eventStore.remove(event, span: .thisEvent, commit: false)
        }
    }

    func commit() async throws {
        try lock.withLock {
            try eventStore.commit()
        }
    }

    func rollback() async {
        lock.withLock {
            eventStore.reset()
            cachedCalendar = nil
        }
    }

    // MARK: - Private helpers; callers must hold `lock`.

    private func apply(_ fields: EventFields, to event: EKEvent) {
        event.title = fields.title
        event.location = fields.location
        event.startDate = fields.start
        event.endDate = fields.end
    }

    /// Returns the event with `storeID` if it exists in the Business calendar, else nil.
    private func existingEvent(storeID: String) throws -> EKEvent? {
        let calendar = try businessCalendar()
        guard let event = eventStore.calendarItem(withIdentifier: storeID) as? EKEvent,
            event.calendar?.calendarIdentifier == calendar.calendarIdentifier
        else { return nil }
        return event
    }

    /// Returns the iCloud "Business" calendar, creating it when it does not exist.
    private func businessCalendar() throws -> EKCalendar {
        if let cachedCalendar { return cachedCalendar }
        let existing = eventStore.calendars(for: .event).first {
            $0.title == Self.calendarTitle && Self.isICloud($0.source)
        }
        if let existing {
            cachedCalendar = existing
            return existing
        }
        guard let source = eventStore.sources.first(where: Self.isICloud) else {
            throw EventKitStoreError.iCloudSourceNotFound
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = Self.calendarTitle
        calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        cachedCalendar = calendar
        return calendar
    }

    private static func isICloud(_ source: EKSource?) -> Bool {
        source?.sourceType == .calDAV && source?.title == "iCloud"
    }
}
