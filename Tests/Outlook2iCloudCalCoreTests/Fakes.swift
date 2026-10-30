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

/// An in-memory calendar that applies writes immediately and records every call.
actor FakeStore: CalendarStore {
    private(set) var events: [String: StoredEvent]
    private(set) var added: [PlannedAdd] = []
    private(set) var updated: [PlannedUpdate] = []
    private(set) var deleted: [String] = []
    private(set) var commitCount = 0
    private let addError: (any Error)?

    init(_ events: [StoredEvent] = [], addError: (any Error)? = nil) {
        self.events = Dictionary(
            events.map { ($0.storeID, $0) }, uniquingKeysWith: { first, _ in first })
        self.addError = addError
    }

    var writeCount: Int { added.count + updated.count + deleted.count }

    func events(in range: DateInterval) async throws -> [StoredEvent] {
        events.values
            .filter { $0.fields.end > range.start && $0.fields.start < range.end }
            .sorted { ($0.fields.start, $0.storeID) < ($1.fields.start, $1.storeID) }
    }

    func add(meetingId: String, fields: EventFields) async throws {
        if let addError { throw addError }
        let storeID = UUID().uuidString
        events[storeID] = StoredEvent(storeID: storeID, meetingId: meetingId, fields: fields)
        added.append(PlannedAdd(meetingId: meetingId, fields: fields))
    }

    func update(storeID: String, fields: EventFields) async throws {
        guard let old = events[storeID] else { throw FakeError(description: "no \(storeID)") }
        events[storeID] = StoredEvent(storeID: storeID, meetingId: old.meetingId, fields: fields)
        updated.append(PlannedUpdate(storeID: storeID, fields: fields))
    }

    func delete(storeID: String) async throws {
        guard events.removeValue(forKey: storeID) != nil else {
            throw FakeError(description: "no \(storeID)")
        }
        deleted.append(storeID)
    }

    func commit() async throws {
        commitCount += 1
    }
}
