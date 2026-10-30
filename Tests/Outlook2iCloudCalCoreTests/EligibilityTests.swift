import Testing

@testable import Outlook2iCloudCalCore

struct EligibilityTests {
    @Test func eligibility() {
        #expect(Eligibility.evaluate(event(response: "Accept")) == nil)
        #expect(Eligibility.evaluate(event(response: "Organizer", subject: "Block")) == nil)
        #expect(Eligibility.evaluate(event(response: "Decline")) == .response("Decline"))
        #expect(Eligibility.evaluate(event(response: "Accept", subject: "Declined: X")) == .declined)
        #expect(Eligibility.evaluate(event(response: "Accept", subject: "Canceled: X")) == .canceled)
        #expect(Eligibility.evaluate(event(response: "Accept", isCanceled: true)) == .canceled)
        #expect(Eligibility.evaluate(event(response: "Accept", isAllDay: true)) == .allDay)
        #expect(Eligibility.evaluate(event(response: "Tentative")) == .response("Tentative"))
        #expect(Eligibility.evaluate(event(response: "NotResponded")) == .response("NotResponded"))
    }

    @Test func responseMatchIsExact() {
        #expect(Eligibility.evaluate(event(response: "")) == .response(""))
        #expect(Eligibility.evaluate(event(response: "accept")) == .response("accept"))
    }

    @Test func reasonPrecedence() {
        let canceled = event(response: "Decline", subject: "Canceled: X", isAllDay: true, isCanceled: true)
        #expect(Eligibility.evaluate(canceled) == .canceled)
        let declined = event(response: "Decline", subject: "Declined: X", isAllDay: true)
        #expect(Eligibility.evaluate(declined) == .declined)
        let allDay = event(response: "Decline", isAllDay: true)
        #expect(Eligibility.evaluate(allDay) == .allDay)
    }

    @Test func prefixOnlyAtStart() {
        #expect(Eligibility.evaluate(event(subject: "Re: Canceled: X")) == nil)
    }

    @Test func dedupeKeepsFirst() {
        let first = event(id: "m1", subject: "First", start: "2026-10-29T10:00:00", end: "2026-10-29T11:00:00")
        let other = event(id: "m2")
        let dup = event(id: "m1", subject: "Second", start: "2026-10-29T10:00:00", end: "2026-10-29T11:00:00")
        #expect(dedupeByMeetingId([first, other, dup]) == [first, other])
    }
}
