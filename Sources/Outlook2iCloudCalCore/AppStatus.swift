import Foundation

/// The colored mark drawn on the menu bar icon.
public enum IconBadge: Equatable, Sendable {
    case none
    /// A red "!" for an expired certificate, a discarded fetch, or a failure.
    case alert
    /// An orange "⏸" while deletions are held.
    case paused
}

/// What the menu bar shows about past syncs.
public struct AppStatus: Equatable, Sendable {
    public var lastOutcome: SyncOutcome?
    /// When a sync last wrote to the calendar, including runs that held deletions.
    public var lastSuccessAt: Date?
    public var lastCounts: SyncCounts?

    public init(
        lastOutcome: SyncOutcome? = nil, lastSuccessAt: Date? = nil, lastCounts: SyncCounts? = nil
    ) {
        self.lastOutcome = lastOutcome
        self.lastSuccessAt = lastSuccessAt
        self.lastCounts = lastCounts
    }

    public var badge: IconBadge {
        switch lastOutcome {
        case .certificateExpired, .incompleteFetch, .failed: .alert
        case .heldDeletions: .paused
        case .success, nil: .none
        }
    }

    /// The text of the first menu row, or nil when the last sync went normally. The text is
    /// looked up in the app's string catalog and stays English where none is loaded.
    public var banner: String? {
        switch lastOutcome {
        case .certificateExpired:
            return String(localized: "Certificate expired. Run mwinit.")
        case .incompleteFetch:
            return String(localized: "Fetch was incomplete. Sync skipped.")
        case .heldDeletions(let counts, let managed, _):
            let percent =
                managed == 0
                ? 100 : Int((Double(counts.held) / Double(managed) * 100).rounded())
            return String(
                localized: "\(counts.held) deletions on hold (\(percent)% of \(managed) managed)")
        case .failed:
            return String(localized: "Sync failed. Check the log.")
        case .success, nil:
            return nil
        }
    }

    /// Records `outcome`; runs that wrote to the calendar also update
    /// `lastSuccessAt` and `lastCounts`.
    public func applying(_ outcome: SyncOutcome, at date: Date) -> AppStatus {
        var next = self
        next.lastOutcome = outcome
        switch outcome {
        case .success(let counts), .heldDeletions(let counts, _, _):
            next.lastSuccessAt = date
            next.lastCounts = counts
        case .certificateExpired, .incompleteFetch, .failed:
            break
        }
        return next
    }
}
