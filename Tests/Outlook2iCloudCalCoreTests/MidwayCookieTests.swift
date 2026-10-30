import Foundation
import Testing

@testable import Outlook2iCloudCalCore

struct MidwayCookieTests {
    private let sample = [
        "# Netscape HTTP Cookie File",
        "midway-auth.amazon.com\tFALSE\t/\tTRUE\t1793000000\tuser_name\tdummy",
        "#HttpOnly_midway-auth.amazon.com\tFALSE\t/\tTRUE\t1793390167\tsession\tdummy",
        "midway-auth.amazon.com\tFALSE\t/\tTRUE\t1793000001\tamazon_enterprise_access\tdummy",
    ].joined(separator: "\n")

    @Test func readsSessionExpiry() {
        #expect(MidwayCookie.sessionExpiry(in: sample) == Date(timeIntervalSince1970: 1_793_390_167))
    }

    @Test func readsDotPrefixedDomain() {
        let text = ".midway-auth.amazon.com\tTRUE\t/\tTRUE\t1793390167\tsession\tdummy"
        #expect(MidwayCookie.sessionExpiry(in: text) == Date(timeIntervalSince1970: 1_793_390_167))
    }

    @Test func ignoresOtherCookies() {
        let text = [
            "midway-auth.amazon.com\tFALSE\t/\tTRUE\t1793000000\tuser_name\tdummy",
            "midway-auth.amazon.com\tFALSE\t/\tTRUE\t1793000001\tamazon_enterprise_access\tdummy",
            "other.example.com\tFALSE\t/\tTRUE\t1793000002\tsession\tdummy",
            "# midway-auth.amazon.com\tFALSE\t/\tTRUE\t1793000003\tsession\tdummy",
        ].joined(separator: "\n")
        #expect(MidwayCookie.sessionExpiry(in: text) == nil)
    }

    @Test func expiredSessionIsInvalid() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "cookie")
        try sample.write(to: file, atomically: true, encoding: .utf8)
        let expiry = Date(timeIntervalSince1970: 1_793_390_167)
        #expect(MidwayCookie.isValid(fileURL: file, now: expiry.addingTimeInterval(-1)))
        #expect(!MidwayCookie.isValid(fileURL: file, now: expiry.addingTimeInterval(1)))
        #expect(!MidwayCookie.isValid(fileURL: dir.appending(path: "missing"), now: expiry))
    }
}
