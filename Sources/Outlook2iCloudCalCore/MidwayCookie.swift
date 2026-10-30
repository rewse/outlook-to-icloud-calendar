import Foundation

/// Reads the expiry of the Midway session cookie from a Netscape cookie file.
public enum MidwayCookie {
    private static let domain = "midway-auth.amazon.com"
    private static let httpOnlyPrefix = "#HttpOnly_"

    /// Returns the expiry of the `session` cookie for the Midway domain, or nil when absent.
    ///
    /// Only the domain, name, and expiry fields are examined; the cookie value is never read.
    public static func sessionExpiry(in contents: String) -> Date? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 7 else { continue }
            var host = String(fields[0])
            if host.hasPrefix(httpOnlyPrefix) {
                host.removeFirst(httpOnlyPrefix.count)
            } else if host.hasPrefix("#") {
                continue
            }
            if host.hasPrefix(".") { host.removeFirst() }
            guard host == domain, fields[5] == "session", let seconds = TimeInterval(fields[4]) else {
                continue
            }
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    /// False when the file is missing, has no session cookie, or the cookie has expired at `now`.
    public static func isValid(fileURL: URL, now: Date) -> Bool {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8),
            let expiry = sessionExpiry(in: contents)
        else { return false }
        return expiry > now
    }
}
