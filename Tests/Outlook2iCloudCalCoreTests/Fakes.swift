import Foundation

@testable import Outlook2iCloudCalCore

struct FakeError: Error, CustomStringConvertible {
    let description: String
}

/// Returns a canned result per bucket, keyed by the interval's start date.
/// An interval with no entry returns no events.
struct FakeSource: OutlookSource {
    var results: [Date: Result<[OutlookEvent], any Error>] = [:]

    func fetch(_ interval: DateInterval) async throws -> [OutlookEvent] {
        try results[interval.start]?.get() ?? []
    }
}

/// Which store call fails, and after how many successful calls of that kind.
enum FakeStoreFailure {
    case add(after: Int = 0)
    case update(after: Int = 0)
    case delete(after: Int = 0)
    case commit
}

/// An in-memory calendar that stages writes in `events`, records every call,
/// and restores the last committed state on `rollback()`.
actor FakeStore: CalendarStore {
    private(set) var events: [String: StoredEvent]
    private(set) var added: [PlannedAdd] = []
    private(set) var updated: [PlannedUpdate] = []
    private(set) var deleted: [String] = []
    private(set) var commitCount = 0
    private(set) var rollbackCount = 0
    private var committed: [String: StoredEvent]
    private let failure: FakeStoreFailure?
    private let error: FakeError

    init(
        _ events: [StoredEvent] = [], failing failure: FakeStoreFailure? = nil,
        error: FakeError = FakeError(description: "store failure")
    ) {
        self.events = Dictionary(
            events.map { ($0.storeID, $0) }, uniquingKeysWith: { first, _ in first })
        self.committed = self.events
        self.failure = failure
        self.error = error
    }

    var writeCount: Int { added.count + updated.count + deleted.count }

    func events(in range: DateInterval) async throws -> [StoredEvent] {
        events.values
            .filter { $0.fields.end > range.start && $0.fields.start < range.end }
            .sorted { ($0.fields.start, $0.storeID) < ($1.fields.start, $1.storeID) }
    }

    func add(meetingId: String, fields: EventFields) async throws {
        if case .add(let after) = failure, added.count >= after { throw error }
        let storeID = UUID().uuidString
        events[storeID] = StoredEvent(storeID: storeID, meetingId: meetingId, fields: fields)
        added.append(PlannedAdd(meetingId: meetingId, fields: fields))
    }

    func update(storeID: String, fields: EventFields) async throws {
        if case .update(let after) = failure, updated.count >= after { throw error }
        guard let old = events[storeID] else { throw FakeError(description: "no \(storeID)") }
        events[storeID] = StoredEvent(storeID: storeID, meetingId: old.meetingId, fields: fields)
        updated.append(PlannedUpdate(storeID: storeID, fields: fields))
    }

    func delete(storeID: String) async throws {
        if case .delete(let after) = failure, deleted.count >= after { throw error }
        guard events.removeValue(forKey: storeID) != nil else {
            throw FakeError(description: "no \(storeID)")
        }
        deleted.append(storeID)
    }

    func commit() async throws {
        if case .commit = failure { throw error }
        commitCount += 1
        committed = events
    }

    func rollback() async {
        rollbackCount += 1
        events = committed
    }
}
