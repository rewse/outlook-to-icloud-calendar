import Foundation

public struct NotificationContent: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Decides when a sync outcome deserves a macOS notification.
public enum NotificationPolicy {
    static let title = "Outlook2iCloudCal"

    /// Notifies when an anomaly starts, when its kind changes, or when the
    /// number of held deletions grows. Success and an expired certificate
    /// never notify, since the certificate expires every morning.
    public static func decide(previous: SyncOutcome?, current: SyncOutcome)
        -> NotificationContent?
    {
        switch current {
        case .success, .certificateExpired:
            return nil
        case .heldDeletions(let counts, _):
            if case .heldDeletions(let previousCounts, _) = previous,
                counts.held <= previousCounts.held
            {
                return nil
            }
        case .incompleteFetch:
            if case .incompleteFetch = previous { return nil }
        case .failed:
            if case .failed = previous { return nil }
        }
        guard let body = AppStatus(lastOutcome: current).banner else { return nil }
        return NotificationContent(title: title, body: body)
    }
}
