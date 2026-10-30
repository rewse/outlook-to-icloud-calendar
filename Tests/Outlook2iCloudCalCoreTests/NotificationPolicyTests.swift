import Foundation
import Testing

@testable import Outlook2iCloudCalCore

private func held(_ count: Int) -> SyncOutcome {
    .heldDeletions(SyncCounts(held: count), managed: 50, storeIDs: [])
}

private let incomplete = SyncOutcome.incompleteFetch(bucketCounts: [1, 0, 1, 1, 1, 1, 1])

@Test func notifyOnTransitionOnly() {
    #expect(
        NotificationPolicy.decide(previous: nil, current: incomplete)
            == NotificationContent(
                title: "Outlook2iCloudCal", body: "Fetch was incomplete. Sync skipped."))
    #expect(NotificationPolicy.decide(previous: incomplete, current: incomplete) == nil)

    let success = SyncOutcome.success(SyncCounts())
    #expect(NotificationPolicy.decide(previous: success, current: .certificateExpired) == nil)
    #expect(NotificationPolicy.decide(previous: nil, current: .certificateExpired) == nil)
    #expect(NotificationPolicy.decide(previous: incomplete, current: success) == nil)
    #expect(NotificationPolicy.decide(previous: nil, current: success) == nil)

    #expect(
        NotificationPolicy.decide(previous: success, current: .failed("x"))
            == NotificationContent(
                title: "Outlook2iCloudCal", body: "Sync failed. Check the log."))
    #expect(NotificationPolicy.decide(previous: .failed("x"), current: .failed("y")) == nil)
    #expect(NotificationPolicy.decide(previous: .certificateExpired, current: .failed("y")) != nil)

    #expect(
        NotificationPolicy.decide(previous: incomplete, current: held(6))
            == NotificationContent(
                title: "Outlook2iCloudCal", body: "6 deletions on hold (12% of 50 managed)"))
    #expect(NotificationPolicy.decide(previous: held(6), current: held(6)) == nil)
    #expect(NotificationPolicy.decide(previous: held(6), current: held(5)) == nil)
    #expect(NotificationPolicy.decide(previous: held(6), current: held(8)) != nil)
}
