import Foundation

/// Encodes a meeting ID into the URL stored on a mirrored event, so the event can be matched
/// back to its Outlook source.
public enum EventURL {
    private static let scheme = "outlook2icloudcal"
    private static let host = "event"

    /// Characters left unescaped in the path; everything else, including "/" and "+", is escaped.
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    /// Returns `outlook2icloudcal://event/<percent-encoded meetingId>`.
    public static func make(meetingId: String) -> URL {
        let encoded = meetingId.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "\(scheme)://\(host)/\(encoded)")!
    }

    /// Returns the meeting ID in `url`, or nil for a nil URL or a URL of another scheme.
    public static func meetingId(from url: URL?) -> String? {
        guard let url, url.scheme == scheme, url.host == host else { return nil }
        let path = url.absoluteString.dropFirst("\(scheme)://\(host)/".count)
        return path.removingPercentEncoding
    }
}
