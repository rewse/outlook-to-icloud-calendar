# リリースに DMG を付ける 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `v*` のタグで、今の自己署名の証明書で署名した DMG を GitHub Actions が作り、GitHub Release に付ける。

**Architecture:** 検査を小さなシェルスクリプトに分け（タグと版、署名の designated requirement）、`make dmg` と CI の両方から呼ぶ。CI はランナーの一時キーチェーンに `.p12` を読み込むスクリプトを使う。同じスクリプトを、pull request で使い捨ての証明書を使って動かし、Secrets なしで CI の署名の道筋を確かめる。

**Tech Stack:** bash、`codesign`、`security`、`hdiutil`、`openssl`、python3（`plistlib`）、GitHub Actions（`macos-26`、`ubuntu-latest`）、`gh`。

**Spec:** `docs/superpowers/specs/2026-10-30-release-dmg-design.md`

## Global Constraints

- 証明書の名前 `Outlook2iCloudCal Developer`、SHA-1 `3D32056B38F1558154EE67CD2903679137FC8A31`、bundle ID `io.github.rewse.Outlook2iCloudCal`
- ad-hoc 署名に逃げない。designated requirement に `certificate root = H"<SHA-1 の小文字>"` が無ければ失敗する
- DMG は `build/Outlook2iCloudCal-<version>.dmg`、ボリューム名 `Outlook2iCloudCal`、UDZO。中身は `Outlook2iCloudCal.app`、`/Applications` へのリンク、`README.txt`。横に `<dmg のファイル名>.sha256`（`shasum -a 256` の出力の形）
- Secrets は environment `release` の `SIGNING_CERTIFICATE_P12`（base64）と `SIGNING_CERTIFICATE_PASSWORD`。`dmg` job だけが `environment: release` を持つ
- タグと `CFBundleShortVersionString` の検査は `gh release create` より前。`release.yml` の名前は変えない
- `.p12` とパスワードをログ、成果物、リポジトリに残さない。一時ファイルと一時キーチェーンは `if: always()` で消す
- 作業者は本人のログインキーチェーンを変えない（`security import`、`add-trusted-cert`、`delete-*` をログインキーチェーンに対して実行しない）。証明書の書き出しもしない
- `README.md` に社内のツールの名前を出さない。文書とコメントは英語、Conventional Commits
- コミットの前に `git add` してから `uvx --with pre-commit-uv==4.3.0 pre-commit@4.6.2 run --all-files`（actionlint、zizmor、shellcheck を含む）

## Review Focus

1. タグ `v0.2.0` と `Info.plist` の `0.1.0` のようにずれていると、Release を作らずに止まる: Task 1 のテスト
2. 一時キーチェーンの証明書が別物（作り直した、Secrets を入れ違えた）だと、DMG を上げずに止まる: Task 1 のテスト（別の SHA-1 で失敗）と Task 3 の使い捨ての証明書の job
3. `make install` で `~/Applications` に入れていた人が DMG を `/Applications` にも入れ、同じアプリが 2 つになる: Task 2 の `README.txt` と Task 4 の README に置き換え先を書く
4. ブラウザで落とした DMG のアプリが開けない（quarantine）: Task 2 の `README.txt` と Task 4 の README に、「このまま開く」と `xattr -dr com.apple.quarantine` を書く
5. pull request の workflow から Secrets が読める: Task 3 で `environment: release` を `dmg` job だけに付け、使い捨ての job は Secrets を参照しないことを確かめる

---

### Task 1: タグと版、署名の検査

**Files:**
- Create: `scripts/signing-certificate-sha1`（1 行、`3D32056B38F1558154EE67CD2903679137FC8A31`）、`scripts/check-tag-version.sh`、`scripts/check-signature.sh`
- Test: `scripts/tests/test_release_checks.sh`

**Interfaces:**
- Produces: `scripts/check-tag-version.sh <tag> [<Info.plist>]`（既定 `Resources/Info.plist`。`<tag>` が `v` + `CFBundleShortVersionString` なら 0、違えば `error: tag <tag> does not match CFBundleShortVersionString <version>` を stderr に出して 1。python3 の `plistlib` で読む。ubuntu でも動く）
- Produces: `scripts/check-signature.sh <app>`（期待する SHA-1 は環境変数 `EXPECTED_SIGNING_SHA1`、無ければ `scripts/signing-certificate-sha1`。`codesign -d -r-` の出力に `identifier "io.github.rewse.Outlook2iCloudCal" and certificate root = H"<小文字>"` があり、`codesign --verify --deep --strict` が通れば 0。違えば理由を stderr に出して 1）

- [ ] **Step 1: 失敗するテストを書く。** 一時ディレクトリに版 `0.1.0` の `Info.plist` を置き、`v0.1.0` で 0、`v0.2.0` と `0.1.0`（`v` なし）で 1 と上のメッセージ。`check-signature.sh` は、ad-hoc 署名（`codesign -s -`）した小さな .app で 1、存在しないパスで 1。ログインキーチェーンの証明書を使うケースは入れない
- [ ] **Step 2: 失敗を確かめる** Run: `bash scripts/tests/test_release_checks.sh` / Expected: FAIL（スクリプトが無い）
- [ ] **Step 3: 2 本のスクリプトと SHA-1 のファイルを書く**
- [ ] **Step 4: 確かめる** Run: `bash scripts/tests/test_release_checks.sh` / Expected: PASS。Run: `scripts/check-signature.sh ~/Applications/Outlook2iCloudCal.app` / Expected: 0（読むだけ）。Run: `EXPECTED_SIGNING_SHA1=0000000000000000000000000000000000000000 scripts/check-signature.sh ~/Applications/Outlook2iCloudCal.app` / Expected: 1
- [ ] **Step 5: pre-commit を通してコミット** `build: check the release tag and the signing certificate`

### Task 2: `make dmg`

**Files:**
- Create: `scripts/build-dmg.sh`、`Resources/DMG-README.txt`
- Modify: `Makefile`（`dmg: app` → `scripts/build-dmg.sh`。`.PHONY` に足す）

**Interfaces:**
- Consumes: `scripts/check-signature.sh`
- Produces: `make dmg` が `build/Outlook2iCloudCal-<version>.dmg` と `.sha256` を作り、パスを出す。`<version>` は `Info.plist` の `CFBundleShortVersionString`

- [ ] **Step 1: スクリプトを書く。** `build/Outlook2iCloudCal.app` に `check-signature.sh` をかけ、失敗なら止める。`mktemp -d build/dmg.XXXXXX` に .app（`ditto`）、`ln -s /Applications`、`README.txt` を置き、`hdiutil create -volname Outlook2iCloudCal -srcfolder <dir> -format UDZO -ov` で作る。`.sha256` は `build/` に入ってから `shasum -a 256 <名前>` で書く（パスを含めない）
- [ ] **Step 2: `README.txt` を書く（英語）。** ドラッグして入れること、`make install` で `~/Applications` に入れている人はそこで置き換えること、初回とバージョンを上げるたびのシステム設定 → Privacy & Security → Open Anyway か `xattr -dr com.apple.quarantine <app のパス>`、カレンダーと通知の許可は残ること、ソースからビルドした版から移ると一度だけ許可を聞かれること
- [ ] **Step 3: 確かめる。** Run: `make dmg`。Expected: DMG と `.sha256` ができる。`hdiutil attach -nobrowse -readonly` した中の .app に `scripts/check-signature.sh` が 0、`ls` で 3 つが見える、`shasum -a 256 -c` が OK。終わったら `hdiutil detach`。Run: `EXPECTED_SIGNING_SHA1=0000000000000000000000000000000000000000 make dmg` / Expected: DMG を作らずに 1
- [ ] **Step 4: pre-commit を通してコミット** `feat: build a signed DMG with make dmg`

### Task 3: CI

**Files:**
- Create: `scripts/ci-import-signing-identity.sh`
- Modify: `.github/workflows/release.yml`、`.github/workflows/test.yml`

**Interfaces:**
- Consumes: `scripts/check-tag-version.sh`、`make dmg`
- Produces: `scripts/ci-import-signing-identity.sh <p12 のパス>`（パスワードは環境変数 `P12_PASSWORD`。`$RUNNER_TEMP` に一時キーチェーンを作って読み込み、`codesign` が確認なしで使えるようにし、検索の並びに足す。キーチェーンのパスを `$GITHUB_ENV` の `SIGNING_KEYCHAIN` に書く。`CI` が `true` でなければ何もせず 1 で止める）

- [ ] **Step 1: 読み込みのスクリプトを書く。** 自己署名の証明書を codesign が使えるようにするのに信頼の設定が要るかを、ランナーで確かめられるように作る（`security find-identity -v -p codesigning` に出ることを最後に確かめ、出なければ 1）。ローカルでは実行しない
- [ ] **Step 2: `release.yml`。** `release` job の Create の前に `scripts/check-tag-version.sh "$TAG_NAME"`。`dmg` job を足す: `needs: release`、`runs-on: macos-26`、`environment: release`、`permissions: contents: write`、checkout（SHA で固定、`persist-credentials: false`）、`.p12` を `$RUNNER_TEMP` に base64 で戻す、`ci-import-signing-identity.sh`、`check-tag-version.sh`、`make dmg`（`DEVELOPER_DIR` を付ける）、`gh release upload "$TAG_NAME" <dmg> <sha256> --clobber`、`if: always()` で `.p12` を消してキーチェーンを `security delete-keychain`。Secrets は `env:` で渡し、`run:` に `${{ }}` で埋め込まない
- [ ] **Step 3: `test.yml` に `dmg-smoke` job を足す。** `runs-on: macos-26`、environment なし、Secrets を参照しない。`openssl` で CN `Outlook2iCloudCal Developer` の使い捨ての証明書と `.p12` を `$RUNNER_TEMP` に作り（`create-signing-identity.sh` と同じ拡張）、`ci-import-signing-identity.sh` で読み込み、その SHA-1 を `EXPECTED_SIGNING_SHA1` にして `make dmg`、DMG を開いて `check-signature.sh`。後片付けは `if: always()`
- [ ] **Step 4: 確かめる。** Run: pre-commit（actionlint、zizmor、shellcheck）/ Expected: PASS。`rg -n "secrets\." .github/workflows/test.yml` / Expected: `dmg-smoke` の中に出ない。ランナーでの確認は、controller が本人に確かめて push したあとの pull request の `dmg-smoke` で行う。失敗したら Step 1 に戻る
- [ ] **Step 5: コミット** `ci: attach a signed DMG to each release`

### Task 4: 文書

**Files:**
- Modify: `README.md`（Requirements、Install、`Releases carry no prebuilt app` の段落）、`AGENTS.md`（Build and test に `make dmg`、Releases）

- [ ] **Step 1: `README.md`。** Install を「Install the DMG」（Release から落とす、ドラッグ、置き換え先、初回とバージョンを上げるたびの開き方、許可）と「Build from source」（今の手順）に分ける。Requirements の Xcode を「Build from source のときだけ」にする。ソースからビルドした版から DMG に移ると一度だけ許可を聞かれることを書く。社内のツールの名前を出さない
- [ ] **Step 2: `AGENTS.md`。** `make dmg` を足す。Releases を書き直す: タグで Release と DMG ができること、版がずれると Release を作らずに止まること、リポジトリの中が原因で `dmg` job が失敗したら直して新しいパッチ版のタグを切ること。本人がする一度きりの準備（environment `release` をタグ `v*` だけに限って作る、`Outlook2iCloudCal Developer` の 1 つだけを `.p12` に書き出す、`base64` にして 2 つの Secrets に入れる、書き出したファイルを消す）を具体的なコマンドかキーチェーンアクセスの操作で書く。証明書を作り直したら、Secrets と `scripts/signing-certificate-sha1` の両方を変えること
- [ ] **Step 3: 確かめる。** Run: `rg -n -i "prebuilt|build from the tag" README.md AGENTS.md` / Expected: 古い説明が残らない。Run: `rg -n -i "aws-outlook|mwinit|midway" README.md` / Expected: 出力なし。pre-commit / Expected: PASS
- [ ] **Step 4: コミット** `docs: install from the release DMG`

### MR のあと（controller と本人が行う）

- push（fox を経由する）と pull request は本人に確かめてから行う。`dmg-smoke` が通ることを確かめる
- マージのあと、本人が AGENTS.md の一度きりの準備をする。次のタグで `dmg` job が通り、Release に DMG と `.sha256` が付くことを確かめる
