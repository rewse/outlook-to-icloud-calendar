import Foundation

public enum SyncMode: Equatable, Sendable {
    /// Apply the plan, holding deletions that trip the deletion gate.
    case normal
    /// Apply the plan, deleting the planned deletions whose store IDs the user
    /// approved without the deletion gate. Any other planned deletions still
    /// go through the gate.
    case approveDeletions(Set<String>)
    /// Delete every event in the window and add all eligible events again.
    case reset
}

extension SyncMode: CustomStringConvertible {
    /// A log label that shows how many deletions were approved, not their IDs.
    public var description: String {
        switch self {
        case .normal: "normal"
        case .approveDeletions(let storeIDs): "approveDeletions(\(storeIDs.count))"
        case .reset: "reset"
        }
    }
}

public struct SyncCounts: Equatable, Codable, Sendable {
    public var added = 0, updated = 0, deleted = 0, held = 0

    public init(added: Int = 0, updated: Int = 0, deleted: Int = 0, held: Int = 0) {
        self.added = added
        self.updated = updated
        self.deleted = deleted
        self.held = held
    }
}

public enum SyncOutcome: Equatable, Sendable {
    case success(SyncCounts)
    /// Adds, updates, and approved deletions were applied; the `counts.held`
    /// deletions listed in `storeIDs` were not.
    case heldDeletions(SyncCounts, managed: Int, storeIDs: [String])
    case certificateExpired
    case incompleteFetch(bucketCounts: [Int])
    case failed(String)
}

/// Mirrors Outlook events into the calendar store. Nothing is written unless
/// every bucket of the window was fetched and returned at least one event.
public struct SyncEngine: Sendable {
    private let source: OutlookSource
    private let store: CalendarStore
    private let log: SyncLog
    private let calendar: Calendar

    public init(source: OutlookSource, store: CalendarStore, log: SyncLog, calendar: Calendar) {
        self.source = source
        self.store = store
        self.log = log
        self.calendar = calendar
    }

    public func run(_ mode: SyncMode, now: Date) async -> SyncOutcome {
        let format = SyncLogFormat(calendar: calendar)
        let window = SyncWindow(now: now, calendar: calendar)
        log.write("sync start mode=\(mode) window=\(format.span(window.range))")

        var fetched: [OutlookEvent] = []
        for (index, bucket) in window.buckets.enumerated() {
            let prefix = "bucket \(index) \(format.span(bucket))"
            do {
                let events = try await source.fetch(bucket)
                log.write("\(prefix) fetched=\(events.count)")
                fetched += events
            } catch let error as FetchError {
                log.write("\(prefix) error: \(error)")
                return finish(
                    error == .certificateExpired ? .certificateExpired : .failed("\(error)"))
            } catch {
                log.write("\(prefix) error: \(error)")
                return finish(.failed(String(describing: error)))
            }
        }

        let inWindow = dedupeByMeetingId(fetched).filter {
            window.contains(start: $0.start, end: $0.end)
        }
        let bucketCounts = window.bucketCounts(inWindow)
        guard !bucketCounts.contains(0) else {
            log.write("gate1 discard bucketCounts=\(bucketCounts)")
            return finish(.incompleteFetch(bucketCounts: bucketCounts))
        }
        log.write("gate1 pass bucketCounts=\(bucketCounts)")

        var exclusions: [ExclusionReason: Int] = [:]
        let desired = inWindow.filter { event in
            guard let reason = Eligibility.evaluate(event) else { return true }
            exclusions[reason, default: 0] += 1
            return false
        }
        log.write("\(format.exclusions(exclusions)) eligible=\(desired.count)")

        do {
            let stored = try await store.events(in: window.range)
            let outcome =
                mode == .reset
                ? try await reset(desired: desired, stored: stored, window: window, format: format)
                : try await apply(
                    desired: desired, stored: stored, window: window, mode: mode, format: format)
            try await store.commit()
            return finish(outcome)
        } catch {
            // Discard staged writes so a later commit cannot persist a partial run.
            await store.rollback()
            log.write("store error: \(error); staged changes rolled back")
            return finish(.failed(String(describing: error)))
        }
    }

    private func reset(
        desired: [OutlookEvent], stored: [StoredEvent], window: SyncWindow, format: SyncLogFormat
    ) async throws -> SyncOutcome {
        var counts = SyncCounts()
        for item in stored where window.contains(start: item.fields.start, end: item.fields.end) {
            log.write(format.event("delete", item.fields))
            try await store.delete(storeID: item.storeID)
            counts.deleted += 1
        }
        for event in desired {
            let fields = EventFields(event)
            log.write(format.event("add", fields))
            try await store.add(meetingId: event.meetingId, fields: fields)
            counts.added += 1
        }
        return .success(counts)
    }

    private func apply(
        desired: [OutlookEvent], stored: [StoredEvent], window: SyncWindow, mode: SyncMode,
        format: SyncLogFormat
    ) async throws -> SyncOutcome {
        let plan = SyncPlan.make(desired: desired, stored: stored, window: window)
        var counts = SyncCounts()
        for add in plan.adds {
            log.write(format.event("add", add.fields))
            try await store.add(meetingId: add.meetingId, fields: add.fields)
            counts.added += 1
        }
        for update in plan.updates {
            log.write(format.event("update", update.fields))
            try await store.update(storeID: update.storeID, fields: update.fields)
            counts.updated += 1
        }

        var pending = plan.deletes
        if case .approveDeletions(let approvedIDs) = mode {
            let approved = pending.filter { approvedIDs.contains($0.storeID) }
            pending.removeAll { approvedIDs.contains($0.storeID) }
            log.write("gate2 approved deletes=\(approved.count)")
            for item in approved {
                log.write(format.event("delete", item.fields))
                try await store.delete(storeID: item.storeID)
                counts.deleted += 1
            }
        }

        let gateSummary = "deletes=\(pending.count) managed=\(plan.managedCount)"
        if SyncPlan.exceedsDeletionGate(deletes: pending.count, managed: plan.managedCount) {
            log.write("gate2 hold \(gateSummary)")
            for item in pending {
                log.write(format.event("held", item.fields))
            }
            counts.held = pending.count
            return .heldDeletions(
                counts, managed: plan.managedCount, storeIDs: pending.map(\.storeID))
        }
        log.write("gate2 pass \(gateSummary)")
        for item in pending {
            log.write(format.event("delete", item.fields))
            try await store.delete(storeID: item.storeID)
            counts.deleted += 1
        }
        return .success(counts)
    }

    private func finish(_ outcome: SyncOutcome) -> SyncOutcome {
        let format = SyncLogFormat(calendar: calendar)
        switch outcome {
        case .success(let counts):
            log.write("sync success \(format.counts(counts))")
        case .heldDeletions(let counts, let managed, _):
            log.write("sync held-deletions \(format.counts(counts)) managed=\(managed)")
        case .certificateExpired:
            log.write("sync certificate-expired")
        case .incompleteFetch(let bucketCounts):
            log.write("sync incomplete-fetch bucketCounts=\(bucketCounts)")
        case .failed(let message):
            log.write("sync failed: \(message)")
        }
        return outcome
    }
}
