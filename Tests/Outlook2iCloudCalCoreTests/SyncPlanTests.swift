import Foundation
import Testing

@testable import Outlook2iCloudCalCore

private let window = SyncWindow(now: tokyo("2026-11-10T12:00:00"), calendar: cal)

private func fields(
    _ title: String = "Sample", location: String? = nil,
    start: String = "2026-11-02T10:00:00", end: String = "2026-11-02T11:00:00"
) -> EventFields {
    EventFields(title: title, location: location, start: tokyo(start), end: tokyo(end))
}

private func stored(_ id: String, _ meetingId: String?, _ fields: EventFields = fields())
    -> StoredEvent
{
    StoredEvent(storeID: id, meetingId: meetingId, fields: fields)
}

private func plan(deletes: Int, managed: Int) -> SyncPlan {
    SyncPlan(
        adds: [], updates: [],
        deletes: (0..<deletes).map { stored("s\($0)", "m\($0)") }, managedCount: managed)
}

@Test func addsUpdatesDeletes() {
    let desired = [event(id: "A"), event(id: "B", subject: "New")]
    let storedEvents = [stored("sB", "B", fields("Old")), stored("sC", "C")]
    let result = SyncPlan.make(desired: desired, stored: storedEvents, window: window)
    #expect(result.adds == [PlannedAdd(meetingId: "A", fields: EventFields(desired[0]))])
    #expect(result.updates == [PlannedUpdate(storeID: "sB", fields: EventFields(desired[1]))])
    #expect(result.deletes == [storedEvents[1]])
    #expect(result.managedCount == 2)
}

@Test func unmanagedEventsAreNeverDeleted() {
    let result = SyncPlan.make(
        desired: [], stored: [stored("u1", nil), stored("u2", nil)], window: window)
    #expect(result.deletes.isEmpty)
    #expect(result.managedCount == 0)
}

@Test func emptyLocationEqualsNil() {
    let desired = event(id: "A")
    #expect(desired.location == "")
    let result = SyncPlan.make(
        desired: [desired], stored: [stored("sA", "A", fields(location: nil))], window: window)
    #expect(result.updates.isEmpty)
    #expect(result.adds.isEmpty)
    #expect(result.deletes.isEmpty)
}

@Test func storedEventEndingAtRangeStartIsIgnored() {
    let edge = fields(
        start: "2026-10-09T23:00:00", end: "2026-10-10T00:00:00")
    #expect(edge.end == window.range.start)
    let result = SyncPlan.make(desired: [], stored: [stored("sE", "E", edge)], window: window)
    #expect(result.deletes.isEmpty)
    #expect(result.managedCount == 0)
}

@Test func storedEventStraddlingRangeStartIsManaged() {
    let straddle = fields(start: "2026-10-09T23:00:00", end: "2026-10-10T01:00:00")
    let result = SyncPlan.make(desired: [], stored: [stored("sS", "S", straddle)], window: window)
    #expect(result.deletes.count == 1)
    #expect(result.managedCount == 1)
}

@Test func duplicateManagedEventsKeepOneDeleteRest() {
    let desired = event(id: "A")
    let first = stored("s1", "A", EventFields(desired))
    let second = stored("s2", "A", EventFields(desired))
    let result = SyncPlan.make(desired: [desired], stored: [first, second], window: window)
    #expect(result.adds.isEmpty)
    #expect(result.updates.isEmpty)
    #expect(result.deletes == [second])
    #expect(result.managedCount == 2)
}

@Test func duplicateOfNoLongerDesiredEventIsDeletedTwice() {
    let storedEvents = [stored("s1", "A"), stored("s2", "A")]
    let result = SyncPlan.make(desired: [], stored: storedEvents, window: window)
    #expect(result.deletes == storedEvents)
}

@Test func deletionGateThresholds() {
    #expect(plan(deletes: 10, managed: 100).exceedsDeletionGate)
    #expect(!plan(deletes: 9, managed: 100).exceedsDeletionGate)
    #expect(!plan(deletes: 4, managed: 20).exceedsDeletionGate)
    #expect(plan(deletes: 5, managed: 40).exceedsDeletionGate)
}
