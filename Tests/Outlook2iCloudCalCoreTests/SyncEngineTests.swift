import Foundation
import Testing

@testable import Outlook2iCloudCalCore

private let now = tokyo("2026-10-30T09:00:00")
private let window = SyncWindow(now: now, calendar: cal)

/// Days inside buckets 0 through 6 of `window`.
private let bucketDays = [
    "2026-10-05", "2026-11-05", "2026-12-05", "2027-01-05", "2027-02-05", "2027-03-05",
    "2027-04-05",
]

/// One accepted event per bucket so that Gate 1 passes.
private func filler(_ index: Int, subject: String = "Sample") -> OutlookEvent {
    event(
        id: "fill-\(index)", subject: subject, start: "\(bucketDays[index])T10:00:00",
        end: "\(bucketDays[index])T11:00:00")
}

private func extra(_ id: String, bucket: Int = 1, hour: Int = 13) -> OutlookEvent {
    let day = bucketDays[bucket]
    return event(
        id: id, subject: "Extra \(id)", start: "\(day)T\(hour):00:00", end: "\(day)T\(hour):30:00")
}

private func stored(_ event: OutlookEvent, managed: Bool = true, title: String? = nil)
    -> StoredEvent
{
    let fields = EventFields(event)
    return StoredEvent(
        storeID: "s-\(event.meetingId)", meetingId: managed ? event.meetingId : nil,
        fields: EventFields(
            title: title ?? fields.title, location: fields.location, start: fields.start,
            end: fields.end))
}

private func source(_ buckets: [[OutlookEvent]], failing: (Int, any Error)? = nil) -> FakeSource {
    var results: [Date: Result<[OutlookEvent], any Error>] = [:]
    for (index, events) in buckets.enumerated() {
        results[window.buckets[index].start] = .success(events)
    }
    if let (index, error) = failing {
        results[window.buckets[index].start] = .failure(error)
    }
    return FakeSource(results: results)
}

private let fillers = (0..<7).map { [filler($0)] }

private func makeLog() -> (SyncLog, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SyncEngineTests-\(UUID().uuidString)")
    return (SyncLog(directory: directory, now: { now }), directory)
}

private func logText(_ directory: URL) throws -> String {
    let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
}

private func engine(_ source: FakeSource, _ store: FakeStore, log: SyncLog? = nil) -> SyncEngine {
    SyncEngine(source: source, store: store, log: log ?? makeLog().0, calendar: cal)
}

@Test func normalSyncAppliesPlan() async throws {
    var buckets = fillers
    buckets[1].append(extra("new"))
    let store = FakeStore(
        (0..<6).map { stored(filler($0)) } + [
            stored(filler(6), title: "Old"), stored(extra("gone", bucket: 2)),
        ])
    let outcome = await engine(source(buckets), store).run(.normal, now: now)
    #expect(outcome == .success(SyncCounts(added: 1, updated: 1, deleted: 1)))
    #expect(await store.added.map(\.meetingId) == ["new"])
    #expect(await store.updated.map(\.storeID) == ["s-fill-6"])
    #expect(await store.deleted == ["s-gone"])
    #expect(await store.commitCount == 1)
}

@Test func certificateExpiredWritesNothing() async {
    let store = FakeStore([stored(extra("gone"))])
    let outcome = await engine(source(fillers, failing: (3, FetchError.certificateExpired)), store)
        .run(.normal, now: now)
    #expect(outcome == .certificateExpired)
    #expect(await store.writeCount == 0)
    #expect(await store.commitCount == 0)
}

@Test func otherFetchErrorsBecomeFailed() async {
    let store = FakeStore()
    let timedOut = await engine(source(fillers, failing: (0, FetchError.timedOut)), store)
        .run(.normal, now: now)
    guard case .failed = timedOut else {
        Issue.record("expected .failed, got \(timedOut)")
        return
    }
    let other = await engine(source(fillers, failing: (5, FakeError(description: "boom"))), store)
        .run(.normal, now: now)
    #expect(other == .failed("boom"))
    #expect(await store.writeCount == 0)
    #expect(await store.commitCount == 0)
}

@Test func emptyBucketDiscardsRun() async {
    var buckets = fillers
    buckets[6] = []
    let store = FakeStore([stored(extra("gone"))])
    let outcome = await engine(source(buckets), store).run(.normal, now: now)
    #expect(outcome == .incompleteFetch(bucketCounts: [1, 1, 1, 1, 1, 1, 0]))
    #expect(await store.writeCount == 0)
    #expect(await store.commitCount == 0)
}

@Test func outOfWindowEventsDoNotPassGate1() async {
    var buckets = fillers
    // An event the source returns for the last bucket but that ends before the window.
    buckets[6] = [event(id: "early", start: "2026-09-01T10:00:00", end: "2026-09-01T11:00:00")]
    let outcome = await engine(source(buckets), FakeStore()).run(.normal, now: now)
    #expect(outcome == .incompleteFetch(bucketCounts: [1, 1, 1, 1, 1, 1, 0]))
}

@Test func emptyCallDiscardsRunEvenWhenItsBucketIsFilled() async throws {
    var buckets = fillers
    // Call 2 also returns an event on bucket 3's first day, but call 3 returns nothing.
    buckets[2].append(event(id: "edge", start: "2026-12-30T10:00:00", end: "2026-12-30T11:00:00"))
    buckets[3] = []
    let store = FakeStore([stored(extra("gone"))])
    let (log, directory) = makeLog()
    let outcome = await engine(source(buckets), store, log: log).run(.normal, now: now)
    #expect(outcome == .incompleteFetch(bucketCounts: [1, 1, 2, 0, 1, 1, 1]))
    #expect(await store.writeCount == 0)
    #expect(await store.commitCount == 0)
    let text = try logText(directory)
    #expect(
        text.contains(
            "gate1 discard bucketCounts=[1, 1, 1, 1, 1, 1, 1] callCounts=[1, 1, 2, 0, 1, 1, 1]"))
}

@Test func declinedOnlyBucketPassesGate1() async {
    var buckets = fillers
    buckets[6] = [
        event(
            id: "d1", response: "Decline", subject: "Declined: Review",
            start: "2027-04-05T10:00:00", end: "2027-04-05T11:00:00"),
    ]
    let store = FakeStore()
    let outcome = await engine(source(buckets), store).run(.normal, now: now)
    #expect(outcome == .success(SyncCounts(added: 6)))
    #expect(await store.commitCount == 1)
}

/// 20 managed events: the 7 fillers plus 13 extras, with fill-6 out of date.
private func massDeletionSetup() -> (FakeSource, FakeStore) {
    let extras = (0..<13).map { extra("x-\($0)", hour: 8 + $0) }
    var buckets = fillers
    buckets[1] += extras.prefix(7) + [extra("new", bucket: 2)]
    let store = FakeStore(
        (0..<6).map { stored(filler($0)) } + [stored(filler(6), title: "Old")]
            + extras.map { stored($0) })
    return (source(buckets), store)
}

@Test func massDeletionIsHeld() async throws {
    let (source, store) = massDeletionSetup()
    let (log, directory) = makeLog()
    let outcome = await engine(source, store, log: log).run(.normal, now: now)
    #expect(
        outcome
            == .heldDeletions(
                SyncCounts(added: 1, updated: 1, held: 6), managed: 20,
                storeIDs: (7..<13).map { "s-x-\($0)" }))
    #expect(await store.added.map(\.meetingId) == ["new"])
    #expect(await store.updated.map(\.storeID) == ["s-fill-6"])
    #expect(await store.deleted.isEmpty)
    #expect(await store.commitCount == 1)
    let text = try logText(directory)
    #expect(text.contains("held \"Extra x-7\" 2026-11-05 15:00-15:30"))
    #expect(text.contains("gate2 hold deletes=6 managed=20"))
}

@Test func approveDeletionsBypassesGate2() async {
    let (source, store) = massDeletionSetup()
    let approved = Set((7..<13).map { "s-x-\($0)" })
    let outcome = await engine(source, store).run(.approveDeletions(approved), now: now)
    #expect(outcome == .success(SyncCounts(added: 1, updated: 1, deleted: 6)))
    #expect(Set(await store.deleted) == approved)
    #expect(await store.commitCount == 1)
}

@Test func approvalDeletesOnlyApprovedEventsAndHoldsTheRest() async throws {
    // 60 managed extras vanish from Outlook, but only 6 of them were approved.
    let extras = (0..<60).map { extra("v-\($0)", bucket: $0 % 7, hour: 8 + $0 / 7) }
    let store = FakeStore((0..<7).map { stored(filler($0)) } + extras.map { stored($0) })
    let approved = Set((0..<6).map { "s-v-\($0)" })
    let (log, directory) = makeLog()
    let outcome = await engine(source(fillers), store, log: log)
        .run(.approveDeletions(approved), now: now)
    guard case .heldDeletions(let counts, let managed, let storeIDs) = outcome else {
        Issue.record("expected .heldDeletions, got \(outcome)")
        return
    }
    #expect(counts == SyncCounts(deleted: 6, held: 54))
    #expect(managed == 67)
    #expect(Set(storeIDs) == Set((6..<60).map { "s-v-\($0)" }))
    #expect(Set(await store.deleted) == approved)
    #expect(await store.commitCount == 1)
    let text = try logText(directory)
    #expect(text.contains("sync start mode=approveDeletions(6)"))
    #expect(text.contains("gate2 approved deletes=6"))
    #expect(text.contains("gate2 hold deletes=54 managed=67"))
}

@Test func approvalIgnoresEventsNoLongerPlannedForDeletion() async {
    var buckets = fillers
    buckets[1].append(extra("back"))
    let store = FakeStore(
        (0..<7).map { stored(filler($0)) } + [stored(extra("back")), stored(extra("gone"))])
    let outcome = await engine(source(buckets), store)
        .run(.approveDeletions(["s-back", "s-gone"]), now: now)
    #expect(outcome == .success(SyncCounts(deleted: 1)))
    #expect(await store.deleted == ["s-gone"])
}

@Test func resetReplacesEverythingInRange() async {
    let before = event(id: "before", start: "2026-09-01T10:00:00", end: "2026-09-01T11:00:00")
    let store = FakeStore([
        stored(filler(0)), stored(extra("old")), stored(extra("personal"), managed: false),
        stored(before),
    ])
    let outcome = await engine(source(fillers), store).run(.reset, now: now)
    #expect(outcome == .success(SyncCounts(added: 7, deleted: 3)))
    let remaining = await store.events.values
    let inRange = remaining.filter {
        window.contains(start: $0.fields.start, end: $0.fields.end)
    }
    #expect(Set(inRange.compactMap(\.meetingId)) == Set((0..<7).map { "fill-\($0)" }))
    #expect(inRange.count == 7)
    #expect(remaining.contains { $0.storeID == "s-before" })
    #expect(await store.commitCount == 1)
}

@Test func resetWithFetchFailureKeepsCalendar() async {
    let store = FakeStore([stored(filler(0)), stored(extra("old"))])
    let outcome = await engine(
        source(fillers, failing: (2, FetchError.commandFailed("exit 1"))), store
    ).run(.reset, now: now)
    guard case .failed = outcome else {
        Issue.record("expected .failed, got \(outcome)")
        return
    }
    #expect(await store.events.count == 2)
    #expect(await store.writeCount == 0)
    #expect(await store.commitCount == 0)
}

@Test func storeErrorBecomesFailed() async {
    let store = FakeStore(
        failing: .add(), error: FakeError(description: "calendar is read-only"))
    let outcome = await engine(source(fillers), store).run(.normal, now: now)
    #expect(outcome == .failed("calendar is read-only"))
    #expect(await store.rollbackCount == 1)
    #expect(await store.commitCount == 0)
}

/// A normal run that adds "new", updates fill-6, and deletes "gone".
private func normalRunStore(failing failure: FakeStoreFailure) -> (FakeSource, FakeStore) {
    var buckets = fillers
    buckets[1].append(extra("new"))
    let store = FakeStore(
        (0..<6).map { stored(filler($0)) } + [
            stored(filler(6), title: "Old"), stored(extra("gone", bucket: 2)),
        ], failing: failure)
    return (source(buckets), store)
}

@Test(arguments: [FakeStoreFailure.update(), .delete(), .commit])
func laterStoreErrorRollsBackEarlierWrites(_ failure: FakeStoreFailure) async {
    let (source, store) = normalRunStore(failing: failure)
    let before = await store.events
    let outcome = await engine(source, store).run(.normal, now: now)
    #expect(outcome == .failed("store failure"))
    #expect(await store.added.count == 1)
    #expect(await store.rollbackCount == 1)
    #expect(await store.commitCount == 0)
    #expect(await store.events == before)
}

@Test func resetErrorAfterSomeDeletesRollsBack() async {
    let store = FakeStore(
        [stored(filler(0)), stored(extra("old")), stored(extra("personal"), managed: false)],
        failing: .delete(after: 2))
    let before = await store.events
    let outcome = await engine(source(fillers), store).run(.reset, now: now)
    #expect(outcome == .failed("store failure"))
    #expect(await store.deleted.count == 2)
    #expect(await store.added.isEmpty)
    #expect(await store.rollbackCount == 1)
    #expect(await store.commitCount == 0)
    #expect(await store.events == before)
}

@Test func resetWithEmptyBucketWritesNothing() async {
    var buckets = fillers
    buckets[4] = []
    let store = FakeStore([stored(filler(0)), stored(extra("old"))])
    let outcome = await engine(source(buckets), store).run(.reset, now: now)
    #expect(outcome == .incompleteFetch(bucketCounts: [1, 1, 1, 1, 0, 1, 1]))
    #expect(await store.writeCount == 0)
    #expect(await store.commitCount == 0)
    #expect(await store.events.count == 2)
}

@Test func logDescribesTheRun() async throws {
    var buckets = fillers
    buckets[1] += [
        extra("new"),
        event(
            id: "t1", response: "Tentative", start: "2026-11-06T10:00:00",
            end: "2026-11-06T11:00:00"),
        event(
            id: "t2", response: "Tentative", start: "2026-11-07T10:00:00",
            end: "2026-11-07T11:00:00"),
        event(
            id: "c1", subject: "Canceled: Sync", start: "2026-11-08T10:00:00",
            end: "2026-11-08T11:00:00"),
    ]
    let store = FakeStore(
        (0..<6).map { stored(filler($0)) } + [
            stored(filler(6), title: "Old"), stored(extra("gone", bucket: 2)),
        ])
    let (log, directory) = makeLog()
    let outcome = await engine(source(buckets), store, log: log).run(.normal, now: now)
    #expect(outcome == .success(SyncCounts(added: 1, updated: 1, deleted: 1)))

    let text = try logText(directory)
    #expect(text.contains("sync start mode=normal window=2026-09-30 00:00-2027-04-30 00:00"))
    #expect(text.contains("bucket 1 2026-10-30 00:00-2026-11-30 00:00 fetched=5"))
    #expect(text.contains("bucket 6 2027-03-30 00:00-2027-04-30 00:00 fetched=1"))
    #expect(
        text.contains(
            "gate1 pass bucketCounts=[1, 5, 1, 1, 1, 1, 1] callCounts=[1, 5, 1, 1, 1, 1, 1]"))
    #expect(text.contains("excluded canceled=1 declined=0 allDay=0 response(Tentative)=2"))
    #expect(text.contains("add \"Extra new\" 2026-11-05 13:00-13:30"))
    #expect(text.contains("update \"Sample\" 2027-04-05 10:00-11:00"))
    #expect(text.contains("delete \"Extra gone\" 2026-12-05 13:00-13:30"))
    #expect(text.contains("gate2 pass deletes=1 managed=8"))
    #expect(text.contains("sync success added=1 updated=1 deleted=1 held=0"))
}
