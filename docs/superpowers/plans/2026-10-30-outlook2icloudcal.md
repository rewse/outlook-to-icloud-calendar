# Outlook2iCloudCal 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Outlook の予定を `mcporter` 経由で取得し、iCloud の専用カレンダー `Business` へ片方向で写す macOS メニューバー常駐アプリを作る。

**Architecture:** SwiftPM パッケージを 2 つのターゲットに分ける。`Outlook2iCloudCalCore` は外部に触れない純粋なロジック（解析、範囲、条件、差分、ゲート、同期エンジン、ログ、通知判定）で、`OutlookSource` と `CalendarStore` のプロトコル越しに外部を扱う。`Outlook2iCloudCal` は実行ターゲットで、`mcporter` 呼び出し、EventKit、SwiftUI `MenuBarExtra`、通知、スケジューラ、`SMAppService` を実装する。`.app` は `Makefile` から呼ぶ `scripts/build-app.sh` で組み立て、専用の自己署名証明書で署名する。

**Tech Stack:** Swift 6.4 ツールチェーン（言語モード Swift 5）、SwiftPM、Swift Testing、SwiftUI、EventKit、UserNotifications、ServiceManagement、Xcode 27.1 の SDK、git-cliff、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-10-30-outlook2icloudcal-design.md`

## Global Constraints

- アプリ名 `Outlook2iCloudCal`、リポジトリ `rewse/outlook-to-icloud-calendar`、Bundle ID `io.github.rewse.Outlook2iCloudCal`。
- macOS 15.0 以上（`platforms: [.macOS("15.0")]`）。外部の Swift パッケージには依存しない。
- すべてのビルドとテストは `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` を付けて実行する。`xcode-select` は変更しない。`Makefile` がこれを export する。
- 同期範囲は「取得日の 0 時の 1 カ月前」から「6 カ月後」まで。月単位の 7 区間に分ける。
- 写す項目は開始、終了、件名、場所だけ。写す条件は `response` が `Accept` か `Organizer`、`isCanceled` が false、件名が `Canceled:` と `Declined:` で始まらない、`isAllDay` が false のすべてを満たすもの。
- 書き込み先は iCloud ソースの `Business` カレンダーだけ。
- ゲート 1：7 区間のどれかの生の件数が 0 なら、その回を破棄する。ゲート 2：削除が管理中件数の 10% 以上かつ 5 件以上なら、削除だけを保留する。
- ログは `~/Library/Logs/Outlook2iCloudCal/YYYY-MM-DD.log`。保持期間は 14 日。
- 自動同期の間隔は 15、30、60、180 分から選ぶ。初期値は 60 分。
- UI の文言は日本語。コードのコメントとコミットメッセージは英語（Conventional Commits）。
- テスト、フィクスチャ、README に実際の予定データを入れない。README は英語で書き、社内ツール名（`aws-outlook-mcp`、`mwinit`、Midway）を出さない。

## Review Focus

- 場所が空の予定：Outlook は `""` を返し、EventKit は `nil` を返すので、そのまま比べると毎回「更新」になる。空文字と `nil` は同じ値として比べる（Task 4）。
- 区間の境界で重複する予定：区間ごとの呼び出しが同じ `meetingId` を 2 回返しても、`Business` に 2 件作らない（Task 3）。
- 範囲の開始日をまたぐ予定：開始が範囲より前で終了が範囲内の予定は範囲内として扱い、写したものは消さない。終了が範囲の開始以前の管理中予定は、消しも直しもしない（Task 4、Task 5）。
- `mcporter` が応答しない：1 回の呼び出しは 180 秒でタイムアウトさせ、失敗として扱う。その回は何も書き込まない（Task 6）。
- 同期の二重実行：タイマーとスリープ復帰と手動操作が重なっても、同期は同時に 1 本しか走らない（Task 8）。

---

### Task 1: パッケージ、ビルド、署名の土台

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `scripts/build-app.sh`
- Create: `scripts/create-signing-identity.sh`
- Create: `Resources/Info.plist`
- Create: `Sources/Outlook2iCloudCal/Outlook2iCloudCalApp.swift`
- Create: `Sources/Outlook2iCloudCalCore/Version.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/VersionTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Produces: `make test`、`make app`（`build/Outlook2iCloudCal.app`）、`make install`（`~/Applications/Outlook2iCloudCal.app` へコピーして起動）、`make cert`。以降のタスクのテストコマンドはすべて `make test` か `make test FILTER=<name>`。
- Produces: `public enum AppInfo { public static let name = "Outlook2iCloudCal"; public static let bundleID = "io.github.rewse.Outlook2iCloudCal" }`（`Version.swift`）。

- [ ] **Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import Outlook2iCloudCalCore

@Test func appInfoNames() {
    #expect(AppInfo.name == "Outlook2iCloudCal")
    #expect(AppInfo.bundleID == "io.github.rewse.Outlook2iCloudCal")
}
```

- [ ] **Step 2: `Package.swift` と `Makefile` を書く**

`swift-tools-version: 6.0`。ターゲットは `Outlook2iCloudCalCore`（library）、`Outlook2iCloudCal`（executable、Core に依存）、`Outlook2iCloudCalCoreTests`（test）。全ターゲットに `swiftLanguageModes: [.v5]` を指定する。`Makefile` は `export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer` を置き、`test` は `swift test $(if $(FILTER),--filter $(FILTER))`、`app` は `scripts/build-app.sh`、`install` は `app` のあと `ditto` で `~/Applications/` へコピーして `open` する。`cert` は `scripts/create-signing-identity.sh`。

- [ ] **Step 3: `make test` で失敗を確かめる**

Run: `make test FILTER=appInfoNames`
Expected: `AppInfo` が未定義でコンパイルが失敗する。

- [ ] **Step 4: `Version.swift` と最小のアプリを書く**

`Outlook2iCloudCalApp.swift` は `@main struct Outlook2iCloudCalApp: App` で、`MenuBarExtra { Button("終了") { NSApp.terminate(nil) } } label: { Image(systemName: "calendar") }` だけを持つ。`Info.plist` には `CFBundleIdentifier`、`CFBundleName`、`CFBundleShortVersionString = 0.1.0`、`CFBundleVersion = 1`、`LSUIElement = true`、`LSMinimumSystemVersion = 15.0`、`NSCalendarsFullAccessUsageDescription`（「Outlook の予定を iCloud の Business カレンダーへ書き込むために使います。」）を入れる。

- [ ] **Step 5: 署名用の証明書スクリプトを書く**

`create-signing-identity.sh` は、ログインキーチェーンに `Outlook2iCloudCal Developer` というコード署名用の自己署名証明書がなければ、`openssl` で鍵と証明書（`extendedKeyUsage = codeSigning`、有効期限 10 年）を作って `security import` で取り込む。すでにあれば何もしない。`~/git/MeetNote/install.sh` の同等の処理を参考にする。

- [ ] **Step 6: `.app` を組み立てるスクリプトを書く**

`build-app.sh` は `swift build -c release --product Outlook2iCloudCal` を実行し、`build/Outlook2iCloudCal.app/Contents/{MacOS,Resources}` を作って実行ファイルと `Info.plist` を置く。そのあと `codesign --force --options runtime --sign "Outlook2iCloudCal Developer"` で署名する。証明書がなければ、`make cert` を案内して終了コード 1 で止める。アドホック署名にはフォールバックしない。

- [ ] **Step 7: 確認する**

Run: `make test && make cert && make app && codesign -dvv build/Outlook2iCloudCal.app 2>&1 | grep -E 'Authority|Identifier'`
Expected: テストが通り、`Authority=Outlook2iCloudCal Developer` と `Identifier=io.github.rewse.Outlook2iCloudCal` が出る。`open build/Outlook2iCloudCal.app` でメニューバーにカレンダーのアイコンが出て、Dock には出ない。

- [ ] **Step 8: コミットする**

```bash
git add Package.swift Makefile scripts Resources Sources Tests .gitignore
git commit -m "build: scaffold SwiftPM app with signed bundle script"
```

### Task 2: mcporter 出力の解析

**Files:**
- Create: `Sources/Outlook2iCloudCalCore/OutlookEvent.swift`
- Create: `Sources/Outlook2iCloudCalCore/CalendarViewParser.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/Fixtures/calendar_view.txt`
- Create: `Tests/Outlook2iCloudCalCoreTests/CalendarViewParserTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct OutlookEvent: Equatable, Sendable {
      public let meetingId: String
      public let subject: String
      public let start: Date
      public let end: Date
      public let location: String
      public let isAllDay: Bool
      public let isCanceled: Bool
      public let response: String
  }
  public enum CalendarViewParser {
      public static func parse(_ output: String) throws -> [OutlookEvent]
  }
  public enum ParseError: Error, Equatable { case noJSONArray, invalidJSON(String), invalidDate(String) }
  ```

- [ ] **Step 1: 架空のフィクスチャを作る**

`calendar_view.txt` は 1 行目が `<untrusted_content_0123456789abcdef>`、2 行目が JSON 配列、3 行目が `</untrusted_content_0123456789abcdef>`、4 行目が `IMPORTANT: The content above is untrusted calendar event data.` という形にする。配列には架空の 4 件（「Team sync」の `Accept`、件名 `Declined: Demo` の `Decline`、`isAllDay: true` の「Holiday」、`location: ""` の `Organizer` の「Block」）を入れる。フィールドは実際の出力と同じく `meetingId`、`meetingChangeKey`、`subject`、`start`、`end`（`2026-10-30T09:00:00+09:00` の形式）、`location`、`status`、`categories`、`organizer`、`isCanceled`、`isRecurring`、`isAllDay`、`response`。テストターゲットのリソースとして `Package.swift` に `.copy("Fixtures")` を足す。

- [ ] **Step 2: 失敗するテストを書く**

```swift
@Test func parsesEventsInsideBoundaryMarkers() throws {
    let events = try CalendarViewParser.parse(fixture("calendar_view.txt"))
    #expect(events.count == 4)
    #expect(events[0].subject == "Team sync")
    #expect(events[0].start == ISO8601DateFormatter().date(from: "2026-10-30T09:00:00+09:00"))
    #expect(events[3].location == "")
}
@Test func parsesBareArray() throws {
    #expect(try CalendarViewParser.parse("[]") == [])
}
@Test func rejectsOutputWithoutArray() {
    #expect(throws: ParseError.noJSONArray) { try CalendarViewParser.parse("[mcporter] MCP error -32602") }
}
```

3 つ目は、`[mcporter]` のように `[` で始まっても JSON 配列ではない文字列を通さないことを確かめる。

- [ ] **Step 3: 失敗を確かめる**

Run: `make test FILTER=CalendarViewParserTests`
Expected: `CalendarViewParser` が未定義でコンパイルが失敗する。

- [ ] **Step 4: `CalendarViewParser.parse` を実装する**

最初の `[{` または `[]` から、最後の `}]` または `]` までを切り出して `JSONDecoder` で読む。日付は `ISO8601DateFormatter`（`.withInternetDateTime`）で解析する。余分なフィールドは無視する。

- [ ] **Step 5: テストが通ることを確かめる**

Run: `make test FILTER=CalendarViewParserTests`
Expected: PASS

- [ ] **Step 6: コミットする**

```bash
git add Sources/Outlook2iCloudCalCore Tests Package.swift
git commit -m "feat: parse calendar_view output from mcporter"
```

### Task 3: 同期範囲、区間、写す条件

**Files:**
- Create: `Sources/Outlook2iCloudCalCore/SyncWindow.swift`
- Create: `Sources/Outlook2iCloudCalCore/Eligibility.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/SyncWindowTests.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/EligibilityTests.swift`

**Interfaces:**
- Consumes: `OutlookEvent`（Task 2）。
- Produces:
  ```swift
  public struct SyncWindow: Equatable, Sendable {
      public let range: DateInterval          // start = 0:00 of today - 1 month, end = 0:00 of today + 6 months
      public let buckets: [DateInterval]      // 7 consecutive month-long intervals covering range
      public init(now: Date, calendar: Calendar)
      public func contains(start: Date, end: Date) -> Bool   // end > range.start && start < range.end
      public func bucketIndex(start: Date) -> Int?           // clamps start before range.start to 0; nil when out of range
      public func bucketCounts(_ events: [OutlookEvent]) -> [Int]
  }
  public enum ExclusionReason: Hashable, Sendable {
      case declined, canceled, allDay, response(String)   // response carries the raw value, e.g. "Tentative"
  }
  public enum Eligibility {
      public static func evaluate(_ event: OutlookEvent) -> ExclusionReason?   // nil means copy it
  }
  public func dedupeByMeetingId(_ events: [OutlookEvent]) -> [OutlookEvent]   // keeps first occurrence, preserves order
  ```

- [ ] **Step 1: 失敗するテストを書く**

`Calendar(identifier: .gregorian)` に `TimeZone(identifier: "Asia/Tokyo")` を設定して使う。

```swift
@Test func windowFor20261030() {
    let w = SyncWindow(now: tokyo("2026-10-30T15:12:00"), calendar: cal)
    #expect(w.range.start == tokyo("2026-09-30T00:00:00"))
    #expect(w.range.end == tokyo("2027-04-30T00:00:00"))
    #expect(w.buckets.count == 7)
    #expect(w.buckets[6].start == tokyo("2027-03-30T00:00:00"))
}
@Test func eventStraddlingRangeStartIsInBucketZero() {
    let w = SyncWindow(now: tokyo("2026-10-30T15:12:00"), calendar: cal)
    #expect(w.contains(start: tokyo("2026-09-29T23:00:00"), end: tokyo("2026-09-30T01:00:00")))
    #expect(w.bucketIndex(start: tokyo("2026-09-29T23:00:00")) == 0)
    #expect(!w.contains(start: tokyo("2026-09-29T09:00:00"), end: tokyo("2026-09-30T00:00:00")))
}
@Test func bucketCountsIncludeExcludedEvents()   // a Declined event still counts toward its bucket
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
@Test func dedupeKeepsFirst()   // two events with the same meetingId from adjacent buckets collapse to one
```

1 つの予定が複数の理由に当てはまるときは、`canceled`、`declined`、`allDay`、`response` の順で最初のものを返す。

- [ ] **Step 2: 失敗を確かめる**

Run: `make test FILTER="SyncWindowTests|EligibilityTests"`
Expected: コンパイルが失敗する。

- [ ] **Step 3: 実装する**

月の加算は `calendar.date(byAdding: .month, value:, to:)` で、基準日（今日の 0 時）から毎回直接足す（区間 k の開始は「基準日 + (k-1) カ月」）。`range.end` は「基準日 + 6 カ月」で、最後の区間の終わりと一致させる。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `make test FILTER="SyncWindowTests|EligibilityTests"`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add Sources/Outlook2iCloudCalCore Tests
git commit -m "feat: compute sync window, buckets, and copy eligibility"
```

### Task 4: 差分とゲート

**Files:**
- Create: `Sources/Outlook2iCloudCalCore/CalendarStore.swift`
- Create: `Sources/Outlook2iCloudCalCore/SyncPlan.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/SyncPlanTests.swift`

**Interfaces:**
- Consumes: `OutlookEvent`、`SyncWindow`（Task 2、3）。
- Produces:
  ```swift
  public struct EventFields: Equatable, Sendable {
      public let title: String
      public let location: String?   // "" is normalized to nil in init
      public let start: Date
      public let end: Date
      public init(title: String, location: String?, start: Date, end: Date)
      public init(_ event: OutlookEvent)
  }
  public struct StoredEvent: Equatable, Sendable {
      public let storeID: String       // EKEvent.calendarItemIdentifier
      public let meetingId: String?    // nil when not created by this app
      public let fields: EventFields
  }
  public protocol CalendarStore: Sendable {
      func events(in range: DateInterval) async throws -> [StoredEvent]
      func add(meetingId: String, fields: EventFields) async throws
      func update(storeID: String, fields: EventFields) async throws
      func delete(storeID: String) async throws
      func commit() async throws
  }
  public struct SyncPlan: Equatable, Sendable {
      public var adds: [PlannedAdd]
      public var updates: [PlannedUpdate]
      public var deletes: [StoredEvent]
      public let managedCount: Int
      public static func make(desired: [OutlookEvent], stored: [StoredEvent], window: SyncWindow) -> SyncPlan
      public var exceedsDeletionGate: Bool   // deletes.count >= 5 && deletes.count * 10 >= managedCount
  }
  public struct PlannedAdd: Equatable, Sendable { public let meetingId: String; public let fields: EventFields }
  public struct PlannedUpdate: Equatable, Sendable { public let storeID: String; public let fields: EventFields }
  ```

- [ ] **Step 1: 失敗するテストを書く**

```swift
@Test func addsUpdatesDeletes()          // desired {A,B}, stored managed {B(changed title), C} → adds [A], updates [B], deletes [C]
@Test func unmanagedEventsAreNeverDeleted()   // stored meetingId == nil → not in deletes, not counted in managedCount
@Test func emptyLocationEqualsNil() {
    // desired location "" vs stored location nil → no update
}
@Test func storedEventEndingAtRangeStartIsIgnored()  // stored managed event with end == window.range.start is not deleted
@Test func duplicateManagedEventsKeepOneDeleteRest() // two stored events with the same meetingId → one kept, one in deletes
@Test func deletionGateThresholds() {
    // managed 100, deletes 10 → true; managed 100, deletes 9 → false
    // managed 20, deletes 4 → false (under 5); managed 40, deletes 5 → true
}
```

- [ ] **Step 2: 失敗を確かめる**

Run: `make test FILTER=SyncPlanTests`
Expected: コンパイルが失敗する。

- [ ] **Step 3: `SyncPlan.make` を実装する**

`stored` は `window.contains` を満たすものだけを対象にする。`desired` は呼び出し側が条件判定と重複排除を済ませたものとして受け取る。`managedCount` は、範囲内で `meetingId` を持つ stored の件数。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `make test FILTER=SyncPlanTests`
Expected: PASS

- [ ] **Step 5: コミットする**

```bash
git add Sources/Outlook2iCloudCalCore Tests
git commit -m "feat: plan adds, updates, and deletes with deletion gate"
```

### Task 5: 同期エンジンとログ

**Files:**
- Create: `Sources/Outlook2iCloudCalCore/OutlookSource.swift`
- Create: `Sources/Outlook2iCloudCalCore/SyncEngine.swift`
- Create: `Sources/Outlook2iCloudCalCore/SyncLog.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/Fakes.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/SyncEngineTests.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/SyncLogTests.swift`

**Interfaces:**
- Consumes: Task 2〜4 のすべて。
- Produces:
  ```swift
  public enum FetchError: Error, Equatable { case certificateExpired, commandFailed(String), timedOut, invalidOutput(String) }
  public protocol OutlookSource: Sendable {
      func fetch(_ interval: DateInterval) async throws -> [OutlookEvent]   // throws FetchError
  }
  public enum SyncMode: Sendable { case normal, approveDeletions, reset }
  public struct SyncCounts: Equatable, Codable, Sendable { public var added = 0, updated = 0, deleted = 0, held = 0 }
  public enum SyncOutcome: Equatable, Sendable {
      case success(SyncCounts)
      case heldDeletions(SyncCounts, managed: Int)   // counts.held = number of held deletes
      case certificateExpired
      case incompleteFetch(bucketCounts: [Int])
      case failed(String)
  }
  public struct SyncEngine: Sendable {
      public init(source: OutlookSource, store: CalendarStore, log: SyncLog, calendar: Calendar)
      public func run(_ mode: SyncMode, now: Date) async -> SyncOutcome
  }
  public final class SyncLog: @unchecked Sendable {
      public init(directory: URL, retentionDays: Int = 14, now: @escaping @Sendable () -> Date = Date.init)
      public func write(_ message: String)   // appends "<ISO8601 local time> <message>\n" to YYYY-MM-DD.log
      public func purge()                    // deletes *.log whose file-name date is older than retentionDays
      public var directory: URL { get }
  }
  ```

- [ ] **Step 1: フェイクを書く**

`FakeSource` は区間の開始日をキーに、返す予定の配列か投げるエラーを持つ。`FakeStore` は `StoredEvent` を辞書で持ち、`add`、`update`、`delete`、`commit` の呼び出しを記録する。`add` は `storeID` に UUID を振る。

- [ ] **Step 2: 失敗するテストを書く**

```swift
@Test func normalSyncAppliesPlan()          // outcome .success(added: 1, updated: 1, deleted: 1); store.commitCount == 1
@Test func certificateExpiredWritesNothing() // source throws .certificateExpired on bucket 3 → .certificateExpired; store has no add/update/delete calls
@Test func emptyBucketDiscardsRun()          // bucket 6 returns [] → .incompleteFetch(bucketCounts: [n0,...,0]); no writes
@Test func declinedOnlyBucketPassesGate1()   // bucket containing only Declined events counts > 0 → not incomplete
@Test func massDeletionIsHeld()              // managed 20, desired drops 6 → .heldDeletions(added/updated applied, held: 6, managed: 20); no deletes
@Test func approveDeletionsBypassesGate2()   // same setup with .approveDeletions → .success(deleted: 6)
@Test func resetReplacesEverythingInRange()  // store has managed + unmanaged events in range and one managed event before range → after .reset, in-range events are only the desired ones, the old one remains
@Test func resetWithFetchFailureKeepsCalendar() // source throws → store unchanged
@Test func storeErrorBecomesFailed()        // store.add throws → .failed(message)
```

ログについては、`SyncEngineTests` で、同期 1 回のログに区間ごとの件数、除外の理由ごとの件数（未知の `response` は値も）、追加・更新・削除・保留の件名と日時、結果が含まれることを `contains` で確かめる。`SyncLogTests` は次のとおり。

```swift
@Test func writesDailyFile()      // now = 2026-10-30 → file "2026-10-30.log" contains the message
@Test func purgeRemovesOlderThan14Days() // files 2026-10-15.log (deleted), 2026-10-16.log (kept), notes.txt (kept) at now = 2026-10-30
```

- [ ] **Step 3: 失敗を確かめる**

Run: `make test FILTER="SyncEngineTests|SyncLogTests"`
Expected: コンパイルが失敗する。

- [ ] **Step 4: `SyncEngine.run` を実装する**

処理の順番は次のとおり。

1. `SyncWindow(now:calendar:)` で範囲を決める。
2. 7 区間を順に `fetch` する。`FetchError.certificateExpired` は `.certificateExpired`、それ以外の `FetchError` は `.failed` として、書き込まずに返す。
3. 返った予定を連結して重複を除き、`window.contains` で絞り込む。
4. ゲート 1 として `bucketCounts` を数え、0 の区間があれば `.incompleteFetch` を返す。
5. `Eligibility` で写す予定を選ぶ。
6. `.reset` なら、範囲内の stored をすべて削除してから、写す予定をすべて追加して `commit` する。
7. それ以外なら `SyncPlan.make` で差分を作り、`exceedsDeletionGate && mode == .normal` なら削除を飛ばして `held` に件数を入れる。
8. `commit` する。
9. 各段階でログを書く。

- [ ] **Step 5: `SyncLog` を実装する**

ファイル名の日付と書き込み時刻は、どちらもローカル時刻を使う。書き込みは `FileHandle` で追記し、ディレクトリがなければ作る。書き込みに失敗しても例外は外に出さない。

- [ ] **Step 6: テストが通ることを確かめる**

Run: `make test FILTER="SyncEngineTests|SyncLogTests"`
Expected: PASS

- [ ] **Step 7: コミットする**

```bash
git add Sources/Outlook2iCloudCalCore Tests
git commit -m "feat: add sync engine with fetch gates and daily log"
```

### Task 6: mcporter ソースと証明書の判定

**Files:**
- Create: `Sources/Outlook2iCloudCalCore/MidwayCookie.swift`
- Create: `Sources/Outlook2iCloudCalCore/CommandRunner.swift`
- Create: `Sources/Outlook2iCloudCalCore/MCPorterSource.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/MidwayCookieTests.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/MCPorterSourceTests.swift`

**Interfaces:**
- Consumes: `OutlookSource`、`FetchError`、`CalendarViewParser`（Task 2、5）。
- Produces:
  ```swift
  public enum MidwayCookie {
      // Netscape cookie file; returns expiry of the "session" cookie for midway-auth.amazon.com (lines may start with "#HttpOnly_")
      public static func sessionExpiry(in contents: String) -> Date?
      public static func isValid(fileURL: URL, now: Date) -> Bool   // false when file missing, cookie missing, or expired
  }
  public struct CommandResult: Sendable { public let exitCode: Int32; public let stdout: String; public let stderr: String }
  public protocol CommandRunner: Sendable {
      func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> CommandResult   // throws FetchError.timedOut
  }
  public struct ProcessCommandRunner: CommandRunner { public init() }
  public struct MCPorterSource: OutlookSource {
      public init(runner: CommandRunner,
                  mcporter: URL = URL(fileURLWithPath: "/opt/homebrew/bin/mcporter"),
                  cookieFile: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".midway/cookie"),
                  now: @escaping @Sendable () -> Date = Date.init,
                  calendar: Calendar = .current)
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**

Cookie のテストデータは、実際のファイルと同じ形式で、値だけ架空のものにする（`#HttpOnly_midway-auth.amazon.com\tFALSE\t/\tTRUE\t1793390167\tsession\tdummy`）。

```swift
@Test func readsSessionExpiry()          // == Date(timeIntervalSince1970: 1793390167)
@Test func ignoresOtherCookies()         // only user_name and amazon_enterprise_access lines → nil
@Test func expiredSessionIsInvalid()     // now after expiry → isValid false; missing file → false
@Test func buildsCalendarViewArguments() {
    // interval 2026-10-30〜2026-11-30 (Asia/Tokyo) →
    // ["call", "aws-outlook-mcp.calendar_view", "view=day", "start_date=10-30-2026", "end_date=11-30-2026"]
    // environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"; timeout == .seconds(180)
}
@Test func expiredCookieSkipsCommand()   // runner is never called; throws .certificateExpired
@Test func nonZeroExitWithExpiredCookieAfterRunIsCertificateExpired()
@Test func nonZeroExitIsCommandFailed()  // cookie valid, exit 1, stderr "boom" → .commandFailed containing "boom"
@Test func timeoutPropagates()           // runner throws .timedOut → .timedOut
@Test func garbageOutputIsInvalidOutput()
```

- [ ] **Step 2: 失敗を確かめる**

Run: `make test FILTER="MidwayCookieTests|MCPorterSourceTests"`
Expected: コンパイルが失敗する。

- [ ] **Step 3: 実装する**

`MCPorterSource.fetch` は、まず Cookie を確かめ、無効なら `.certificateExpired` を投げる。有効ならコマンドを実行する。終了コードが 0 以外なら Cookie を確かめ直し、そのときに無効になっていれば `.certificateExpired`、そうでなければ `.commandFailed(stderr の先頭 500 文字)` を投げる。終了コードが 0 なら、stdout を `CalendarViewParser.parse` に渡す。`ParseError` は `.invalidOutput` に包む。`ProcessCommandRunner` は `Process` と `Pipe` で実装し、タイムアウトしたら `terminate()` してから `.timedOut` を投げる。パイプが詰まらないよう、stdout と stderr は終了を待つ前から読み続ける（1 カ月分で約 500KB になる）。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `make test FILTER="MidwayCookieTests|MCPorterSourceTests"`
Expected: PASS

- [ ] **Step 5: コミットする**

実機での取得は Task 8 の手動確認でまとめて確かめる。


```bash
git add Sources/Outlook2iCloudCalCore Tests
git commit -m "feat: fetch Outlook events through mcporter with cookie check"
```

### Task 7: EventKit ストア

**Files:**
- Create: `Sources/Outlook2iCloudCal/EventKitStore.swift`
- Create: `Sources/Outlook2iCloudCalCore/EventURL.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/EventURLTests.swift`

**Interfaces:**
- Consumes: `CalendarStore`、`StoredEvent`、`EventFields`（Task 4）。
- Produces:
  ```swift
  public enum EventURL {
      public static func make(meetingId: String) -> URL      // outlook2icloudcal://event/<percent-encoded meetingId>
      public static func meetingId(from url: URL?) -> String? // nil for other schemes or nil url
  }
  enum EventKitStoreError: Error { case accessDenied, iCloudSourceNotFound }
  final class EventKitStore: CalendarStore {
      static let calendarTitle = "Business"
      init(eventStore: EKEventStore = EKEventStore())
      func requestAccess() async throws          // requestFullAccessToEvents; throws accessDenied
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**

```swift
@Test func roundTripsMeetingIdWithSlashesAndPlus() {
    let id = "AAkALg/abc+def=="
    #expect(EventURL.meetingId(from: EventURL.make(meetingId: id)) == id)
}
@Test func ignoresOtherURLs() { #expect(EventURL.meetingId(from: URL(string: "https://example.com")) == nil) }
```

- [ ] **Step 2: 失敗を確かめてから `EventURL` を実装し、通ることを確かめる**

Run: `make test FILTER=EventURLTests`
Expected: 最初はコンパイルが失敗し、実装後は PASS。

- [ ] **Step 3: `EventKitStore` を実装する**

カレンダーは、`calendars(for: .event)` の中から、タイトルが `Business` で `source.sourceType == .calDAV && source.title == "iCloud"` のものを使う。見つからなければ、同じ条件の source に `EKCalendar(for: .event, eventStore:)` で作って `saveCalendar(_:commit: true)` する。iCloud の source がなければ `iCloudSourceNotFound` を投げる。

`events(in:)` は `predicateForEvents(withStart:end:calendars:)` の結果を `StoredEvent` にする。`meetingId` は `EventURL.meetingId(from: event.url)` で取り出す。`add` は `title`、`location`、`startDate`、`endDate`、`url`、`timeZone = .current` を設定し、`save(_:span: .thisEvent, commit: false)` で保存する。`delete` は `remove(_:span: .thisEvent, commit: false)`。`commit` は `eventStore.commit()`。このクラスは EventKit の外に出ないので、自動テストは書かない。

- [ ] **Step 4: ビルドが通ることを確かめる**

Run: `make app`
Expected: 成功する。

- [ ] **Step 5: コミットする**

```bash
git add Sources Tests
git commit -m "feat: store synced events in the iCloud Business calendar"
```

### Task 8: アプリの状態、スケジューラ、メニュー、通知

**Files:**
- Create: `Sources/Outlook2iCloudCalCore/AppStatus.swift`
- Create: `Sources/Outlook2iCloudCalCore/NotificationPolicy.swift`
- Create: `Sources/Outlook2iCloudCalCore/SyncCoordinator.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/AppStatusTests.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/NotificationPolicyTests.swift`
- Create: `Tests/Outlook2iCloudCalCoreTests/SyncCoordinatorTests.swift`
- Create: `Sources/Outlook2iCloudCal/AppModel.swift`
- Create: `Sources/Outlook2iCloudCal/MenuContent.swift`
- Create: `Sources/Outlook2iCloudCal/StatusIcon.swift`
- Create: `Sources/Outlook2iCloudCal/Notifier.swift`
- Modify: `Sources/Outlook2iCloudCal/Outlook2iCloudCalApp.swift`

**Interfaces:**
- Consumes: `SyncEngine`、`SyncOutcome`、`SyncCounts`、`SyncMode`、`SyncLog`、`MCPorterSource`、`ProcessCommandRunner`、`EventKitStore`。
- Produces:
  ```swift
  public enum IconBadge: Equatable, Sendable { case none, alert, paused }   // alert = red "!", paused = orange "⏸"
  public struct AppStatus: Equatable, Sendable {
      public var lastOutcome: SyncOutcome?
      public var lastSuccessAt: Date?
      public var lastCounts: SyncCounts?
      public var badge: IconBadge { get }      // certificateExpired/incompleteFetch/failed → .alert, heldDeletions → .paused, else .none
      public var banner: String? { get }       // text of the first menu row; nil when normal
      public func applying(_ outcome: SyncOutcome, at date: Date) -> AppStatus   // success/heldDeletions update lastSuccessAt and lastCounts
  }
  public struct NotificationContent: Equatable, Sendable { public let title: String; public let body: String }
  public enum NotificationPolicy {
      public static func decide(previous: SyncOutcome?, current: SyncOutcome) -> NotificationContent?
  }
  public actor SyncCoordinator {
      public init(engine: SyncEngine)
      public func run(_ mode: SyncMode, now: Date) async -> SyncOutcome?   // nil when another run is in progress
  }
  ```

- [ ] **Step 1: 失敗するテストを書く**

`banner` の文言は次の 4 つに決める。

- 証明書切れ：「証明書が切れています。mwinit してください」
- ゲート 1 による破棄：「取得が途中で切れたため同期を見送りました」
- 削除の保留：「削除 N 件を保留中（管理中 M 件の P%）」。P は四捨五入した整数
- その他の失敗：「同期に失敗しました。ログを確認してください」

```swift
@Test func badgeAndBanner() {
    // .certificateExpired → (.alert, "証明書が切れています。mwinit してください")
    // .heldDeletions(held 42, managed 180) → (.paused, "削除 42 件を保留中（管理中 180 件の 23%）")
    // .success → (.none, nil)
}
@Test func certificateExpiredKeepsLastSuccess()   // lastSuccessAt unchanged after .certificateExpired
@Test func notifyOnTransitionOnly() {
    // nil → .incompleteFetch : notify; .incompleteFetch → .incompleteFetch : nil
    // .success → .certificateExpired : nil (never notify cert expiry)
    // .success → .failed("x") : notify; .failed("x") → .failed("y") : nil (same kind)
    // .incompleteFetch → .heldDeletions : notify (kind changed)
    // .heldDeletions(held 6) → .heldDeletions(held 6) : nil; → .heldDeletions(held 8) : notify
}
@Test func coordinatorRejectsConcurrentRun()  // engine with a source that suspends; second run returns nil while first is in flight
```

通知の title は「Outlook2iCloudCal」に固定し、body は `banner` と同じ文言にする。

- [ ] **Step 2: 失敗を確かめてから Core 側を実装し、通ることを確かめる**

Run: `make test FILTER="AppStatusTests|NotificationPolicyTests|SyncCoordinatorTests"`
Expected: 最初はコンパイルが失敗し、実装後は PASS。

- [ ] **Step 3: アプリ側を実装する**

`AppModel` は `@MainActor final class AppModel: ObservableObject` にする。持つものは次のとおり。

- `status: AppStatus`。`lastSuccessAt` と `lastCounts` は `UserDefaults` に保存する。
- `intervalMinutes: Int`。`UserDefaults` のキーは `syncIntervalMinutes`、初期値は 60。
- `func sync(_ mode: SyncMode)`。

起動時の処理は次の順にする。

1. `SyncLog.purge()` を実行する。
2. カレンダーと通知の許可を求める。
3. `SMAppService.mainApp` が未登録なら登録する。
4. すぐに 1 回同期する。

タイマーは `intervalMinutes` ごとに `sync(.normal)` を呼ぶ。`NSWorkspace.didWakeNotification` を受けたときは、最後の試行から間隔以上たっていれば同期する。同期の前に、日付が変わっていれば `purge()` する。

結果が出たら `status.applying` で状態を更新し、`NotificationPolicy.decide` の結果があれば `Notifier` で通知する。カレンダーへのアクセスを拒否されたときは `.failed("カレンダーへのアクセスが許可されていません")` として扱う。

`MenuContent` は、仕様の「メニューバー」の節の順番どおりに並べる。最終同期の時刻は、今日なら `HH:mm`、それ以外なら `M/d HH:mm` で表示し、まだなければ「なし」と出す。直前の同期は「追加 a / 更新 u / 削除 d」と表示し、保留があれば末尾に「（保留 h）」を付ける。間隔のサブメニューは `Picker` で作る。「ログを Finder で表示」は `NSWorkspace.shared.open(log.directory)`。確認ダイアログは `NSAlert` で出す。

- 「初期化して再取得…」：「範囲内（M/d〜M/d）の Business の予定をすべて削除して、Outlook から取り直します。」
- 「削除を実行…」：「保留中の削除 N 件を実行します。」。実行すると `sync(.approveDeletions)` を呼ぶ。

`StatusIcon` は `IconBadge` から `NSImage` を作る。`.none` は SF Symbol `calendar` のテンプレート画像。それ以外は `calendar` に赤い「!」かオレンジの「⏸」を重ねた、テンプレートではない画像にする。同期中はメニューの「今すぐ同期」を無効にして、「同期中…」と表示する。

- [ ] **Step 4: 実機で確認する**

Run: `make install`

確認すること：
- (1) 初回にカレンダーと通知の許可を求められる。
- (2) iCloud に `Business` が作られ、承諾済みの予定だけが入る。辞退、仮承諾、終日、キャンセルの予定は入らない。
- (3) 「今すぐ同期」をもう一度押すと、直前の同期が「追加 0 / 更新 0 / 削除 0」になる。
- (4) `~/Library/Logs/Outlook2iCloudCal/` に当日のログができる。
- (5) `mv ~/.midway/cookie ~/.midway/cookie.bak` のあとで同期すると、アイコンが赤くなって案内が出て、通知は出ない。確認が済んだら元に戻して `mwinit` する。
- (6) 「初期化して再取得…」で確認ダイアログが出て、実行後も件数が変わらない。
- (7) ログアウトしてログインし直すと、アプリが起動している。

- [ ] **Step 5: コミットする**

```bash
git add Sources Tests
git commit -m "feat: add menu bar UI, scheduler, and anomaly notifications"
```

### Task 9: リポジトリの設定、README、リリースの仕組み

**Files:**
- Create: `.github/dependabot.yml`
- Create: `.github/workflows/dependabot-review.yml`
- Create: `.github/workflows/gitleaks.yml`
- Create: `.github/workflows/trufflehog.yml`
- Create: `.github/workflows/lint.yml`
- Create: `.github/workflows/test.yml`
- Create: `.github/workflows/release.yml`
- Create: `.pre-commit-config.yaml`
- Create: `cliff.toml`
- Create: `AGENTS.md`
- Create: `README.md`

**Interfaces:**
- Consumes: `make test`（Task 1）。

- [ ] **Step 1: `~/git/actions` から設定を写す**

`dependabot-review.yml`、`gitleaks.yml`、`trufflehog.yml`、`lint.yml`、`release.yml`、`cliff.toml`、`.pre-commit-config.yaml` を写す。そのうえで次の点を変える。

- `cliff.toml` の Full Changelog の URL を `rewse/outlook-to-icloud-calendar` に変える。
- スケジュール実行のある workflow の cron の分を、`~/git` の下にあるほかのリポジトリと重ならない値に変える（`rg -n "cron:" ~/git/*/.github/workflows` で確かめる）。
- `dependabot.yml` は `github-actions` と `pre-commit` の 2 つのエントリーにする。書式は `~/git/enecoq-data-fetcher/.github/dependabot.yml` と同じで、`default-days: 5` に zizmor の ignore コメントを付け、`github-actions` のエントリーだけ `rewse/*` を cooldown の対象から外す。Swift の依存はないので、`swift` のエントリーは作らない。

lockfile がないので、`dependency-scan.yml` も作らない。

- [ ] **Step 2: `test.yml` を書く**

`runs-on: macos-26`、job 名は `Test`、`permissions: contents: read`、`actions/checkout` は SHA で固定して `persist-credentials: false` にする。テストは `sudo xcode-select` を使わず、`DEVELOPER_DIR` に runner の Xcode のパス（`/Applications/Xcode.app/Contents/Developer`）を渡したうえで `make test` を実行する。

- [ ] **Step 3: `AGENTS.md` と `README.md` を書く**

`AGENTS.md` は英語で書く。中身はビルドとテストのコマンド（`make test`、`make app`、`make install`、`make cert`）、`DEVELOPER_DIR` を使う理由、Core とアプリの分担、テストで実際の iCloud と Outlook に触れないこと、フィクスチャに実データを入れないこと、リリースの手順（`Info.plist` のバージョンを上げてコミットし、`vX.Y.Z` のタグを push する）。

`README.md` は英語で書き、社内ツール名を一般化する。書くのは目的、同期の規則、安全装置、メニュー、インストール手順（`make cert && make install`）、必要なもの。必要なものは「MCP 経由で Outlook カレンダーを返すサーバーを `mcporter` に登録してあること」「認証用の証明書を更新するコマンド」「macOS のカレンダーに iCloud アカウントが登録してあること」「Xcode」。書いたら `~/.agents/skills/humanizer/SKILL.md` に沿って推敲する。

- [ ] **Step 4: lint を通す**

Run: `git add -A && uvx --with pre-commit-uv==4.3.0 pre-commit@4.6.2 run --all-files`
Expected: すべての hook が Passed。zizmor の指摘は抑制せず、直して通す。

- [ ] **Step 5: コミットする**

```bash
git commit -m "ci: add security scans, lint, test, and release workflows"
```

### Task 10: 公開と最初のリリース

GitHub への書き込みを伴うので、各 step の前に本人に確認する。

- [ ] **Step 1: リポジトリを作って push する**

Run: `gh repo create rewse/outlook-to-icloud-calendar --public --source . --push`
Expected: `main` が push され、`Lint`、`Test`、`Gitleaks` が成功する（`gh run list | cat` で確かめる）。

- [ ] **Step 2: タグのルールセットを設定する**

`Protect release tags` を作る。対象は `refs/tags/v*` で、作成、更新、削除を制限し、バイパスできるのはリポジトリの admin ロールだけにする（`gh api repos/rewse/outlook-to-icloud-calendar/rulesets` に POST する。既存リポジトリの設定を `gh api repos/rewse/actions/rulesets | cat` で確かめてそろえる）。

- [ ] **Step 3: v0.1.0 をリリースする**

Run: `git tag v0.1.0 && git push origin v0.1.0`
Expected: `Release` の workflow が成功し、git-cliff のリリースノート付きの GitHub Release `v0.1.0` ができる。`.app` は添付しない。
