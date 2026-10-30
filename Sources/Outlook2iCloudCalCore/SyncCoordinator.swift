import Foundation

/// Runs at most one sync at a time, however many triggers fire at once.
public actor SyncCoordinator {
    private let engine: SyncEngine
    private var isRunning = false

    public init(engine: SyncEngine) {
        self.engine = engine
    }

    /// Runs a sync, or returns nil at once when another run is in progress.
    public func run(_ mode: SyncMode, now: Date) async -> SyncOutcome? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }
        return await engine.run(mode, now: now)
    }
}
