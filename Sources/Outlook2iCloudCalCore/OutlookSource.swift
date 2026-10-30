import Foundation

/// Why fetching events from Outlook failed.
public enum FetchError: Error, Equatable {
    /// The credentials used to reach Outlook have expired and must be renewed.
    case certificateExpired
    case commandFailed(String)
    case timedOut
    case invalidOutput(String)
}

extension FetchError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .certificateExpired: "Outlook credentials have expired"
        case .commandFailed(let detail): "Outlook fetch failed: \(detail)"
        case .timedOut: "Outlook fetch timed out"
        case .invalidOutput(let detail): "Outlook returned invalid output: \(detail)"
        }
    }
}

/// Where Outlook events are read from.
public protocol OutlookSource: Sendable {
    /// Returns the events overlapping `interval`; throws `FetchError` on failure.
    func fetch(_ interval: DateInterval) async throws -> [OutlookEvent]
}
