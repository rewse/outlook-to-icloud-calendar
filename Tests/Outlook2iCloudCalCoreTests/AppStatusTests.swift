import Foundation
import Testing

@testable import Outlook2iCloudCalCore

private struct BannerCase {
    let outcome: SyncOutcome
    let badge: IconBadge
    let banner: String?

    init(_ outcome: SyncOutcome, _ badge: IconBadge, _ banner: String?) {
        self.outcome = outcome
        self.badge = badge
        self.banner = banner
    }
}

@Test func badgeAndBanner() {
    let cases: [BannerCase] = [
        BannerCase(.certificateExpired, .alert, "証明書が切れています。mwinit してください"),
        BannerCase(
            .incompleteFetch(bucketCounts: [1, 0, 1, 1, 1, 1, 1]), .alert,
            "取得が途中で切れたため同期を見送りました"
        ),
        BannerCase(.failed("x"), .alert, "同期に失敗しました。ログを確認してください"),
        BannerCase(
            .heldDeletions(SyncCounts(held: 42), managed: 180, storeIDs: []), .paused,
            "削除 42 件を保留中（管理中 180 件の 23%）"
        ),
        BannerCase(.success(SyncCounts(added: 1)), .none, nil),
    ]
    for testCase in cases {
        let status = AppStatus().applying(testCase.outcome, at: tokyo("2026-10-30T09:00:00"))
        #expect(status.badge == testCase.badge)
        #expect(status.banner == testCase.banner)
    }
    #expect(AppStatus().badge == .none)
    #expect(AppStatus().banner == nil)
}

@Test func heldBannerRoundsAndGuardsZeroManaged() {
    let date = tokyo("2026-10-30T09:00:00")
    let half = AppStatus().applying(
        .heldDeletions(SyncCounts(held: 1), managed: 8, storeIDs: []), at: date)
    #expect(half.banner == "削除 1 件を保留中（管理中 8 件の 13%）")
    let zero = AppStatus().applying(
        .heldDeletions(SyncCounts(held: 5), managed: 0, storeIDs: []), at: date)
    #expect(zero.banner == "削除 5 件を保留中（管理中 0 件の 100%）")
}

@Test func successAndHeldUpdateLastSuccess() {
    let first = tokyo("2026-10-30T09:00:00")
    let second = tokyo("2026-10-30T10:00:00")
    let counts = SyncCounts(added: 2, updated: 1, deleted: 0, held: 6)
    let status = AppStatus()
        .applying(.success(SyncCounts(added: 3)), at: first)
        .applying(.heldDeletions(counts, managed: 50, storeIDs: []), at: second)
    #expect(status.lastSuccessAt == second)
    #expect(status.lastCounts == counts)
    #expect(status.lastOutcome == .heldDeletions(counts, managed: 50, storeIDs: []))
}

@Test func certificateExpiredKeepsLastSuccess() {
    let first = tokyo("2026-10-30T09:00:00")
    let counts = SyncCounts(added: 3)
    let status = AppStatus()
        .applying(.success(counts), at: first)
        .applying(.certificateExpired, at: tokyo("2026-10-30T10:00:00"))
        .applying(.failed("x"), at: tokyo("2026-10-30T11:00:00"))
    #expect(status.lastSuccessAt == first)
    #expect(status.lastCounts == counts)
    #expect(status.lastOutcome == .failed("x"))
}
