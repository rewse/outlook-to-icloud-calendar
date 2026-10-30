import Foundation

public struct PlannedAdd: Equatable, Sendable {
    public let meetingId: String
    public let fields: EventFields

    public init(meetingId: String, fields: EventFields) {
        self.meetingId = meetingId
        self.fields = fields
    }
}

public struct PlannedUpdate: Equatable, Sendable {
    public let storeID: String
    public let fields: EventFields

    public init(storeID: String, fields: EventFields) {
        self.storeID = storeID
        self.fields = fields
    }
}

/// The changes needed to make the calendar match the desired events.
public struct SyncPlan: Equatable, Sendable {
    /// In `desired` order.
    public var adds: [PlannedAdd]
    /// In `stored` order.
    public var updates: [PlannedUpdate]
    /// Managed events with no desired counterpart, plus duplicates of a meeting
    /// already kept; in `stored` order.
    public var deletes: [StoredEvent]
    /// Number of stored events in the window that this app created.
    public let managedCount: Int

    /// Plans changes for stored events overlapping `window`. Events outside the
    /// window and events without a `meetingId` are never updated or deleted.
    /// `desired` must already be filtered for eligibility and de-duplicated.
    public static func make(
        desired: [OutlookEvent], stored: [StoredEvent], window: SyncWindow
    ) -> SyncPlan {
        let desiredById = Dictionary(
            desired.map { ($0.meetingId, $0) }, uniquingKeysWith: { first, _ in first })
        var keptIds = Set<String>()
        var updates: [PlannedUpdate] = []
        var deletes: [StoredEvent] = []
        var managedCount = 0

        for item in stored {
            guard let meetingId = item.meetingId,
                window.contains(start: item.fields.start, end: item.fields.end)
            else { continue }
            managedCount += 1
            guard let wanted = desiredById[meetingId], keptIds.insert(meetingId).inserted else {
                deletes.append(item)
                continue
            }
            let fields = EventFields(wanted)
            if fields != item.fields {
                updates.append(PlannedUpdate(storeID: item.storeID, fields: fields))
            }
        }

        var addedIds = Set<String>()
        let adds = desired.compactMap { event -> PlannedAdd? in
            guard !keptIds.contains(event.meetingId), addedIds.insert(event.meetingId).inserted
            else { return nil }
            return PlannedAdd(meetingId: event.meetingId, fields: EventFields(event))
        }
        return SyncPlan(adds: adds, updates: updates, deletes: deletes, managedCount: managedCount)
    }

    /// Whether the deletions are too many to apply without confirmation:
    /// at least 5 and at least 10% of the managed events.
    public var exceedsDeletionGate: Bool {
        Self.exceedsDeletionGate(deletes: deletes.count, managed: managedCount)
    }

    /// Whether `deletes` deletions out of `managed` managed events trip the gate.
    public static func exceedsDeletionGate(deletes: Int, managed: Int) -> Bool {
        deletes >= 5 && deletes * 10 >= managed
    }
}
