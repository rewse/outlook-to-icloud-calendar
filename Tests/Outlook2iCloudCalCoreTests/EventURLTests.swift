import Foundation
import Testing

@testable import Outlook2iCloudCalCore

@Test func roundTripsMeetingIdWithSlashesAndPlus() {
    let id = "AAkALg/abc+def=="
    #expect(EventURL.meetingId(from: EventURL.make(meetingId: id)) == id)
}

@Test func ignoresOtherURLs() {
    #expect(EventURL.meetingId(from: URL(string: "https://example.com")) == nil)
}

@Test func ignoresNilURL() {
    #expect(EventURL.meetingId(from: nil) == nil)
}

@Test func treatsWhitespaceOnlyLocationAsNil() {
    let date = Date(timeIntervalSince1970: 0)
    #expect(EventFields(title: "T", location: "  ", start: date, end: date).location == nil)
    #expect(EventFields(title: "T", location: " \n\t", start: date, end: date).location == nil)
    #expect(EventFields(title: "T", location: " Room ", start: date, end: date).location == " Room ")
}
