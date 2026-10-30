import AppKit
import Foundation
import Outlook2iCloudCalCore
import ServiceManagement

/// Owns the sync schedule and the state shown in the menu bar.
@MainActor
final class AppModel: ObservableObject {
    static let intervalChoices = [15, 30, 60, 180]
    static let defaultIntervalMinutes = 60

    private enum Key {
        static let interval = "syncIntervalMinutes"
        static let lastCounts = "lastCounts"
        static let lastSuccessAt = "lastSuccessAt"
    }

    @Published private(set) var status: AppStatus
    @Published private(set) var isSyncing = false
    @Published var intervalMinutes: Int {
        didSet {
            defaults.set(intervalMinutes, forKey: Key.interval)
            scheduleTimer()
        }
    }

    let log: SyncLog
    private let defaults: UserDefaults
    private let store = EventKitStore()
    private let coordinator: SyncCoordinator
    private let notifier: Notifier
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastAttemptAt: Date?
    private var lastPurgeAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        log = SyncLog(directory: library.appending(path: "Logs/Outlook2iCloudCal"))
        coordinator = SyncCoordinator(
            engine: SyncEngine(
                source: MCPorterSource(runner: ProcessCommandRunner()), store: store, log: log,
                calendar: .current))
        notifier = Notifier(log: log)
        let stored = defaults.integer(forKey: Key.interval)
        intervalMinutes =
            Self.intervalChoices.contains(stored) ? stored : Self.defaultIntervalMinutes
        status = AppStatus(
            lastSuccessAt: defaults.object(forKey: Key.lastSuccessAt) as? Date,
            lastCounts: defaults.data(forKey: Key.lastCounts).flatMap {
                try? JSONDecoder().decode(SyncCounts.self, from: $0)
            })
        Task { await start() }
    }

    /// The store IDs of the deletions held by the last sync, or nil when none are held.
    /// Approving passes exactly these IDs, so a later, larger plan is not approved with them.
    var heldStoreIDs: [String]? {
        if case .heldDeletions(_, _, let storeIDs) = status.lastOutcome { return storeIDs }
        return nil
    }

    /// The range that a reset clears, as of now.
    var resetWindow: DateInterval {
        SyncWindow(now: Date(), calendar: .current).range
    }

    /// Starts a sync unless one is already running. A dropped request is logged when the
    /// user asked for it, since the menu gives no other sign that it did not run.
    func sync(_ mode: SyncMode, userRequested: Bool = false) {
        guard !isSyncing else {
            if userRequested { logDropped(mode) }
            return
        }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            await performSync(mode, userRequested: userRequested)
        }
    }

    private func start() async {
        purgeLog(Date())
        do {
            try await store.requestAccess()
        } catch {
            log.write("calendar access request failed: \(error)")
        }
        await notifier.requestAuthorization()
        registerLoginItem()
        sync(.normal)
        scheduleTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAfterWakeIfDue() }
        }
    }

    private func logDropped(_ mode: SyncMode) {
        log.write("user-requested sync mode=\(mode) dropped: another sync is running")
    }

    private func performSync(_ mode: SyncMode, userRequested: Bool) async {
        let now = Date()
        lastAttemptAt = now
        if !(lastPurgeAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false) {
            purgeLog(now)
        }
        let outcome: SyncOutcome
        do {
            try await store.requestAccess()
            guard let result = await coordinator.run(mode, now: now) else {
                if userRequested { logDropped(mode) }
                return
            }
            outcome = result
        } catch {
            log.write("sync failed: calendar access denied (\(error))")
            outcome = .failed("カレンダーへのアクセスが許可されていません")
        }
        record(outcome, at: Date())
    }

    private func record(_ outcome: SyncOutcome, at date: Date) {
        if let content = NotificationPolicy.decide(previous: status.lastOutcome, current: outcome) {
            notifier.post(content)
        }
        status = status.applying(outcome, at: date)
        if let lastSuccessAt = status.lastSuccessAt {
            defaults.set(lastSuccessAt, forKey: Key.lastSuccessAt)
        }
        if let counts = status.lastCounts, let data = try? JSONEncoder().encode(counts) {
            defaults.set(data, forKey: Key.lastCounts)
        }
    }

    private func purgeLog(_ now: Date) {
        log.purge()
        lastPurgeAt = now
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(intervalMinutes * 60), repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync(.normal) }
        }
    }

    private func syncAfterWakeIfDue() {
        let interval = TimeInterval(intervalMinutes * 60)
        if let lastAttemptAt, Date().timeIntervalSince(lastAttemptAt) < interval { return }
        sync(.normal)
    }

    private func registerLoginItem() {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            log.write("login item registration failed: \(error)")
        }
    }
}
