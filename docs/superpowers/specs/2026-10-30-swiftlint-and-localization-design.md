# SwiftLint の導入と英語化

## 目的

Swift のコードを SwiftLint で検査し、pre-commit と GitHub Actions の両方で同じ検査を走らせる。あわせて、画面に出る文言をコードからリソースへ切り離し、英語と日本語の両方で使えるようにする。リポジトリは公開しているので、日本語を使わない人も使えるようにすることが英語化の目的である。

## SwiftLint

- `.pre-commit-config.yaml` に `realm/SwiftLint` のフック（`id: swiftlint`）を足し、`rev:` を v0.65.1 のコミット SHA に固定する。フックは `language: swift` で SwiftLint をソースからビルドする。
- `lint.yml` は今のまま `pre-commit run --all-files` を呼ぶ。`ubuntu-latest` のランナーには Swift が入っているので、そこで SwiftLint がビルドされる。CI の時間は数分延びる。
- 設定はリポジトリのルートの `.swiftlint.yml` に置き、既定のルールを使う。対象は `Package.swift`、`Sources`、`Tests`、`scripts` とし、`.build` と `build` を外す。
- フックに `--strict` を付け、警告でも失敗させる。指摘は抑止せずに直す。抑止するときは、`~/git/AGENTS.md` に従って同じ行に理由を書く（設計上の判断）。
- `scripts/make-icon.swift` も対象に含め、指摘のない状態にする（設計上の判断）。
- CI でソースからのビルドが失敗するか、15 分以上かかるときは、却下した `language: system` の方式に切り替え、CI ではリリースのバイナリをチェックサムを確かめて入れる。そのときは本人に報告する（設計上の判断）。

## 英語化

### 方針

- 開発言語は英語とし、日本語の翻訳を付ける。どちらの言語で表示するかは macOS の言語設定に従う。アプリの中に言語の切り替えは置かない。
- 文言は String Catalog に置く。メニュー、ダイアログ、通知の文言は `Resources/Localizable.xcstrings` に、カレンダーの利用目的（`NSCalendarsFullAccessUsageDescription`）は `Resources/InfoPlist.xcstrings` に置く。
- コードでは `String(localized:)` を使い、キーには英語の文言そのものを使う。Core も同じ書き方にする（Foundation だけで書けるので、Core に UI を持ち込まないという決まりには反しない）。
- `scripts/build-app.sh` が `xcrun xcstringstool compile` で両方のカタログをコンパイルし、`Contents/Resources/en.lproj` と `ja.lproj` に置く。`Info.plist` には `CFBundleDevelopmentRegion` に `en` を設定し、利用目的は英語にする。
- 英語で数によって形が変わる文言は、カタログの複数形の機能を使う。対象は時間（1 hour / 3 hours）、保留中の削除（1 deletion on hold / 42 deletions on hold）、削除の確認（1 held event / 6 held events）である。「A added / U updated」のような件数の並びは形が変わらないので対象にしない（設計上の判断）。
- アプリ名「Outlook2iCloudCal」（通知のタイトル）は訳さない。`AppModel` にあるカレンダーへのアクセスが許可されていないときの理由は、ログにしか出ないので英語の文言に置き換え、カタログには入れない。
- ログは今のまま英語だけにする。調べるときに読むもので、翻訳はいらない。`SyncOutcome.failed` の理由もログにしか出ないので、英語のまま翻訳しない。

### テスト

- テストの実行中はカタログが読み込まれないので、`String(localized:)` はキーの英語をそのまま返す。テストが確かめる文言は英語にする。
- カタログの中で日本語の翻訳がないキーがあれば失敗するテストを足す。カタログはテストのソースファイルからの相対パスで読む。

### 英語の文言

| 場所 | 日本語（今の文言） | 英語 |
|---|---|---|
| バナー | 証明書が切れています。mwinit してください | Certificate expired. Run mwinit. |
| バナー | 取得が途中で切れたため同期を見送りました | Fetch was incomplete. Sync skipped. |
| バナー | 削除 N 件を保留中（管理中 M 件の P%） | N deletions on hold (P% of M managed) |
| バナー | 同期に失敗しました。ログを確認してください | Sync failed. Check the log. |
| メニュー | 削除を実行… | Delete Held Events… |
| メニュー | 最終同期：… | Last sync: … |
| メニュー | 直前の同期：追加 A / 更新 U / 削除 D（保留 H） | Last result: A added / U updated / D deleted (H held) |
| メニュー | なし | None |
| メニュー | 今すぐ同期 / 同期中… | Sync Now / Syncing… |
| メニュー | 自動同期の間隔 | Sync Interval |
| メニュー | N 分 / N 時間 | N min / N hour(s) |
| メニュー | ログを Finder で表示 | Show Log in Finder |
| メニュー | 初期化して再取得… | Reset and Refetch… |
| メニュー | 終了 | Quit |
| ダイアログ | 初期化して再取得 / 範囲内（S〜E）の Business の予定をすべて削除して、Outlook から取り直します。 | Reset and Refetch / Deletes every Business event from S to E and fetches them again from Outlook. |
| ダイアログ | 削除を実行 / 保留中の削除 N 件を実行します。 | Delete Held Events / Deletes N held event(s). |
| ダイアログ | 実行 / キャンセル | Run / Cancel |
| 利用目的 | Outlook の予定を iCloud の Business カレンダーへ書き込むために使います。 | Used to write Outlook events to the Business calendar in iCloud. |

日本語の文言は今のものを翻訳としてそのまま使う。英語の文言は builder が調整してよい。

## 検討した方式

| 方式 | 長所 | 短所 |
|---|---|---|
| A. `Resources/` の String Catalog を `xcstringstool` でコンパイルし、`Bundle.main` から引く | `.app` を組み立てる今のスクリプトに数行足すだけで済む。Core と app の両方で同じ書き方ができる | Xcode の文字列抽出が使えないので、カタログを手で書く |
| B. SwiftPM のターゲットのリソースとして持ち、`Bundle.module` から引く | SwiftPM の標準の仕組みに乗る | `Bundle.module` は `.app` の直下にリソースバンドルを探すので、署名が通らない。Core と app でバンドルが分かれる |
| C. Core は文言を持たずに状態だけを返し、app で文言にする | Core のテストが文言から独立する | バナーと通知の組み立てを app 側へ移すことになり、今テストしている部分がテストから外れる |

本人が A を選んだ。

SwiftLint を pre-commit から呼ぶ方法は、公式のフックでソースからビルドする方式と、`language: system` で手元の `swiftlint` を呼び、CI ではリリースのバイナリを入れる方式を比べた。前者は CI の時間が数分延びるが、ローカルと CI で同じバージョンが確実に動き、Dependabot の `pre-commit` エントリがバージョンを上げる。前者にする（設計上の判断）。

## ドキュメント

- README に、表示言語が英語と日本語で、macOS の言語設定に従うことを書く。
- `AGENTS.md` に、画面に出る文言は `String(localized:)` で書き、カタログに英語のキーと日本語の翻訳を足すという決まりを書く。
