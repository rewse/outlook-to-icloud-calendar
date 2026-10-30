import Foundation
import Testing

@testable import Outlook2iCloudCalCore

/// Suspends the first fetch until `open()` is called; later fetches return
/// no events at once.
private actor BlockingSource: OutlookSource {
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var gate: CheckedContinuation<Void, Never>?

    func fetch(_ interval: DateInterval) async throws -> [OutlookEvent] {
        if !hasEntered {
            hasEntered = true
            entryWaiters.forEach { $0.resume() }
            entryWaiters = []
            await withCheckedContinuation { gate = $0 }
        }
        return []
    }

    /// Returns once the first fetch is suspended.
    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        gate?.resume()
        gate = nil
    }
}

@Test func coordinatorRejectsConcurrentRun() async {
    let now = tokyo("2026-10-30T09:00:00")
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SyncCoordinatorTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = BlockingSource()
    let engine = SyncEngine(
        source: source, store: FakeStore(), log: SyncLog(directory: directory, now: { now }),
        calendar: cal)
    let coordinator = SyncCoordinator(engine: engine)

    let first = Task { await coordinator.run(.normal, now: now) }
    await source.waitUntilEntered()
    #expect(await coordinator.run(.normal, now: now) == nil)
    #expect(await coordinator.run(.approveDeletions([]), now: now) == nil)

    await source.open()
    let incomplete = SyncOutcome.incompleteFetch(bucketCounts: [0, 0, 0, 0, 0, 0, 0])
    #expect(await first.value == incomplete)
    #expect(await coordinator.run(.normal, now: now) == incomplete)
}
