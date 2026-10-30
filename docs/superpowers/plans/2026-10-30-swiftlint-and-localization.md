# SwiftLint and Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SwiftLint を pre-commit と CI で走らせ、画面に出る文言を String Catalog に切り離して英語と日本語で表示する。

**Architecture:** SwiftLint は `realm/SwiftLint` の公式フックで動かす。文言は英語をキーにして `String(localized:)` で引き、`Resources/Localizable.xcstrings` と `Resources/InfoPlist.xcstrings` を `build-app.sh` が `xcstringstool` で `.app` の `en.lproj`／`ja.lproj` にコンパイルする。

**Tech Stack:** Swift 6.0 tools / Swift 5 mode, SwiftLint 0.65.1, String Catalog, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-30-swiftlint-and-localization-design.md`

## Global Constraints

- Build and test only through the Makefile with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; never run `xcode-select -s`.
- Pre-commit: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer uvx --with pre-commit-uv==4.3.0 pre-commit@4.6.2 run --all-files` after `git add` of new files. SwiftLint cannot load sourcekitd without `DEVELOPER_DIR`.
- SwiftLint hook: `repo: https://github.com/realm/SwiftLint`, `rev: 6aba03e3d8302b33f106e0f922210f35ca4b52cf  # frozen: 0.65.1`, `id: swiftlint`, `args: [--strict]`.
- Fix lint findings instead of suppressing them. A suppression needs the reason on the same line.
- Source language `en`; Japanese translations are the current Japanese strings verbatim (spec table).
- Logs and `SyncOutcome.failed` reasons stay English and untranslated. The notification title `Outlook2iCloudCal` is not translated.
- Plural variations only for: hours, deletions on hold, held events in the confirm dialog.
- Fixtures and tests contain invented data only. Test output stays free of warnings.
- Commits follow Conventional Commits, in English. Comments describe the code as it is.

## Review Focus

- A key in code that is missing from the catalog silently shows English in Japanese locale → Task 2 test lists every Core and app key and checks it exists in the catalog with a `ja` translation.
- A format key whose specifiers do not match between code and catalog (`%lld` vs `%@`, `%%`) renders garbage → Task 2 renders each format key from the compiled catalog in `en` and `ja` with sample arguments.
- Plural forms: `1 hour`, `1 deletion on hold`, `1 held event` → Task 2 render test asserts the singular and plural English forms.
- Positional arguments in Japanese differ in order from English → Task 2 render test asserts the Japanese reset message with both dates.
- `InfoPlist.xcstrings` compiled into the wrong file name (it must be `InfoPlist.strings`) → Task 3 verification lists the `.lproj` contents.

---

### Task 1: SwiftLint

**Files:**
- Create: `.swiftlint.yml`
- Modify: `.pre-commit-config.yaml`, `AGENTS.md` (Validation section), any Swift file with findings

- [ ] **Step 1: Add the hook** to `.pre-commit-config.yaml` as the last repo, with the values in Global Constraints.

- [ ] **Step 2: Write `.swiftlint.yml`**

```yaml
included:
  - Package.swift
  - Sources
  - Tests
  - scripts
excluded:
  - .build
  - build
# Google Swift style requires trailing commas in multi-line collections.
trailing_comma:
  mandatory_comma: true
# swift-format puts the brace of a multi-line condition on its own line.
opening_brace:
  ignore_multiline_statement_conditions: true
```

Other rules stay at their defaults. If another default rule contradicts Google Swift style as the code already applies it consistently, configure that rule here with a comment saying so; do not disable rules wholesale.

- [ ] **Step 3: Run SwiftLint and fix every finding**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --strict`
Fix by changing the code: rename short identifiers to descriptive ones, split long functions, replace large tuples with small structs, etc. Keep behavior identical.
Expected: `Done linting! Found 0 violations`.

- [ ] **Step 4: Run the tests** — `make test`. Expected: all tests pass, no warnings.

- [ ] **Step 5: Update `AGENTS.md`** Validation section: the pre-commit command is prefixed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` because SwiftLint loads sourcekitd from the Xcode toolchain, and the SwiftLint hook runs `--strict`.

- [ ] **Step 6: Run pre-commit** with the Global Constraints command. Expected: every hook Passed (the first run builds SwiftLint from source and takes a few minutes).

- [ ] **Step 7: Commit** — `git commit -m "ci: lint Swift with SwiftLint"` (code fixes may go in a preceding `style:` or `refactor:` commit).

### Task 2: Catalog and localized strings

**Files:**
- Create: `Resources/Localizable.xcstrings`, `Tests/Outlook2iCloudCalCoreTests/LocalizationTests.swift`
- Modify: `Sources/Outlook2iCloudCalCore/AppStatus.swift`, `Sources/Outlook2iCloudCal/MenuContent.swift`, `Sources/Outlook2iCloudCal/AppModel.swift:121`, `Tests/Outlook2iCloudCalCoreTests/AppStatusTests.swift`, `Tests/Outlook2iCloudCalCoreTests/NotificationPolicyTests.swift`

**Interfaces:**
- Produces: `Resources/Localizable.xcstrings` (sourceLanguage `en`), consumed by Task 3's build script.

Keys (English source, exactly as `String(localized:)` produces them from the interpolations; Int → `%lld`, String → `%@`):

| Key | ja | en plural |
|---|---|---|
| `Certificate expired. Run mwinit.` | 証明書が切れています。mwinit してください | |
| `Fetch was incomplete. Sync skipped.` | 取得が途中で切れたため同期を見送りました | |
| `%lld deletions on hold (%lld%% of %lld managed)` | 削除 %1$lld 件を保留中（管理中 %3$lld 件の %2$lld%%） | one: `%lld deletion on hold (…)` |
| `Sync failed. Check the log.` | 同期に失敗しました。ログを確認してください | |
| `Delete Held Events…` | 削除を実行… | |
| `Last sync: %@` | 最終同期：%@ | |
| `Last result: %@` | 直前の同期：%@ | |
| `%lld added / %lld updated / %lld deleted` | 追加 %1$lld / 更新 %2$lld / 削除 %3$lld | |
| ` (%lld held)` | （保留 %lld） | |
| `None` | なし | |
| `Sync Now` | 今すぐ同期 | |
| `Syncing…` | 同期中… | |
| `Sync Interval` | 自動同期の間隔 | |
| `%lld min` | %lld 分 | |
| `%lld hours` | %lld 時間 | one: `%lld hour` |
| `Show Log in Finder` | ログを Finder で表示 | |
| `Reset and Refetch…` | 初期化して再取得… | |
| `Quit` | 終了 | |
| `Reset and Refetch` | 初期化して再取得 | |
| `Deletes every Business event from %@ to %@ and fetches them again from Outlook.` | 範囲内（%1$@〜%2$@）の Business の予定をすべて削除して、Outlook から取り直します。 | |
| `Delete Held Events` | 削除を実行 | |
| `Deletes %lld held events.` | 保留中の削除 %lld 件を実行します。 | one: `Deletes %lld held event.` |
| `Run` | 実行 | |
| `Cancel` | キャンセル | |

For the multi-argument plural key, use the catalog's `substitutions` so only the first argument selects the form.

- [ ] **Step 1: Write the failing tests**

In `AppStatusTests.swift` and `NotificationPolicyTests.swift`, replace every Japanese expectation with the English text, for example `"Certificate expired. Run mwinit."`, `"42 deletions on hold (23% of 180 managed)"`. In `heldBannerRoundsAndGuardsZeroManaged` change the half case to `held: 3, managed: 8` → `"3 deletions on hold (38% of 8 managed)"` (outside the catalog the plural form is not applied, so tests avoid a count of 1), and the zero case to `"5 deletions on hold (100% of 0 managed)"`.

In `LocalizationTests.swift`:

```swift
@Test func everyKeyHasJapanese()       // decode the catalog JSON; every key in `allKeys` exists and has a ja stringUnit or variations with state "translated"
@Test func catalogHasNoUnusedKeys()    // the catalog's key set == Set(allKeys)
@Test func rendersEnglishAndJapanese() // compile with `xcrun xcstringstool compile` into a mktemp dir, load Bundle(path: <dir>/en.lproj) and ja.lproj, format with String(format:locale:arguments:)
```

`allKeys` is a literal array of the table's keys. `rendersEnglishAndJapanese` asserts at least:
- en `%lld hours` with 1 → `1 hour`, with 3 → `3 hours`; ja with 3 → `3 時間`
- en held key with (1, 13, 8) → `1 deletion on hold (13% of 8 managed)`; with (42, 23, 180) → `42 deletions on hold (23% of 180 managed)`; ja with (42, 23, 180) → `削除 42 件を保留中（管理中 180 件の 23%）`
- en `Deletes %lld held events.` with 1 → `Deletes 1 held event.`
- ja reset message with ("9/30", "4/29") → `範囲内（9/30〜4/29）の Business の予定をすべて削除して、Outlook から取り直します。`

Locate the catalog from `#filePath` (`../../Resources/Localizable.xcstrings`). Run `xcrun` through `Process` with the inherited environment.

- [ ] **Step 2: Run** `make test FILTER='AppStatus|NotificationPolicy|Localization'` — expected FAIL.

- [ ] **Step 3: Implement**

- `AppStatus.banner` returns `String(localized:)` with the keys above.
- `MenuContent` uses `String(localized:)` for every string it shows (buttons, picker label, alert title, message, and buttons). Interval labels: `minutes < 60 ? "%lld min" : "%lld hours"` with `minutes / 60`. The reset message passes the two formatted dates as separate arguments.
- `AppModel.swift:121`: replace the Japanese reason with `"calendar access not granted"` (plain String, not localized).
- Write `Resources/Localizable.xcstrings` with the table.

- [ ] **Step 4: Run** `make test` — expected PASS, no warnings. Then `rg -n '[ぁ-んァ-ヶ一-龠]' Sources` — expected no output.

- [ ] **Step 5: Run pre-commit and commit** — `git commit -m "feat: localize UI strings into English and Japanese"`.

### Task 3: Bundle the catalogs into the app

**Files:**
- Create: `Resources/InfoPlist.xcstrings`
- Modify: `Resources/Info.plist`, `scripts/build-app.sh`, `README.md`, `AGENTS.md`

- [ ] **Step 1: Info.plist** — add `CFBundleDevelopmentRegion` = `en`; set `NSCalendarsFullAccessUsageDescription` to `Used to write Outlook events to the Business calendar in iCloud.`

- [ ] **Step 2: `Resources/InfoPlist.xcstrings`** — key `NSCalendarsFullAccessUsageDescription`, en `Used to write Outlook events to the Business calendar in iCloud.`, ja `Outlook の予定を iCloud の Business カレンダーへ書き込むために使います。`. Add this key to nothing in Task 2's tests; Step 4 verifies it.

- [ ] **Step 3: `build-app.sh`** — after copying `Info.plist`, run `xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"` and the same for `Resources/InfoPlist.xcstrings`, before `codesign`.

- [ ] **Step 4: Verify** — `make app && find build/Outlook2iCloudCal.app/Contents/Resources -name '*.strings*' | sort && plutil -p build/Outlook2iCloudCal.app/Contents/Resources/ja.lproj/InfoPlist.strings`
Expected: `en.lproj` and `ja.lproj` each contain `Localizable.strings` (and `Localizable.stringsdict` for en) plus `InfoPlist.strings`; the ja `InfoPlist.strings` prints the Japanese usage description; `codesign --verify --strict build/Outlook2iCloudCal.app` succeeds.

- [ ] **Step 5: Docs** — README (English): a short paragraph that the menu and notifications are in English and Japanese and follow the macOS language setting. `AGENTS.md`: a "Localization" section — write user-facing text with `String(localized:)` using the English text as the key, add every key to `Resources/Localizable.xcstrings` with a Japanese translation and to `allKeys` in `LocalizationTests.swift`, keep logs and failure reasons English. Read `~/.agents/skills/humanizer/SKILL.md` before writing the README text.

- [ ] **Step 6: Run pre-commit and commit** — `git commit -m "feat: bundle string catalogs into the app"`.
