# リリースに DMG を付ける

## 目的

`v*` のタグを push したら、GitHub Actions が署名済みの DMG を作り、GitHub Release に付ける。主な利用者は本人で、ほかの Mac にソースからビルドせずに入れられるようにする。ほかの人も DMG を使えるが、Outlook の MCP サーバーと証明書のコマンドが要るので、実際に使える人は限られる。

カレンダーの許可は署名の designated requirement（`identifier "io.github.rewse.Outlook2iCloudCal" and certificate root = H"<証明書の SHA-1>"`）に紐づく。CI でも今の「Outlook2iCloudCal Developer」で署名すれば、`make install` で作ったものと DMG のどちらに入れ換えても、許可は出し直しにならない。

## 今の状態

- `release.yml` は `ubuntu-latest` で git-cliff のリリースノートを作り、`gh release create` で Release を作る。ビルドした .app は付けない
- 署名の証明書は本人の Mac のログインキーチェーンにだけある（SHA-1 `3D32056B38F1558154EE67CD2903679137FC8A31`、2026-10-30 作成、10 年有効）
- `AGENTS.md` の Releases と `README.md` の Install は「Release にビルドした app は付けない。タグからビルドする」と書いている
- タグの作成、更新、削除は、ruleset「Protect release tags」で管理者だけに限っている

## 進め方の選択肢

- **A. 今の証明書を `.p12` にして Secrets に置き、タグで CI が署名する（採用。本人が選んだ）**: どこで作っても署名が同じになる。代わりに、開発に使う鍵が GitHub にも置かれる
- **B. リリース専用の証明書を作り、Secrets にだけ置く**: 開発の鍵は Mac から出ない。ただし同じ Mac で DMG 版と `make install` 版を入れ換えるたびに許可の出し直しになる。鍵が漏れたときの影響は A と変わらない
- **C. 本人の Mac で DMG を作り、手で Release に上げる**: 鍵はどこにも出ない。自動にならず、このホストからは GitHub に push できないので中継が要る

## ゴール

- `make dmg` で `build/Outlook2iCloudCal-<version>.dmg` を作る。中身は署名済みの `Outlook2iCloudCal.app`、`/Applications` へのシンボリックリンク、初回の開き方を書いた README
- `release.yml` に macOS の job を足す。Release を作ったあとで、Secrets の証明書で署名した DMG と、その SHA-256 を書いた `.sha256` を Release に付ける
- CI で作った .app の designated requirement が、上の SHA-1 を含むことを確かめる。含まなければ job を失敗させ、DMG を上げない
- タグの名前（`vX.Y.Z`）と `Info.plist` の `CFBundleShortVersionString` が違えば、job を失敗させる
- `README.md` の Install を DMG から入れる手順にし、ソースからのビルドは後ろに残す。`AGENTS.md` の Releases を、DMG を付けることと Secrets の置き場所に合わせて書き直す

## ゴールでないもの

- Developer ID での署名と公証（Apple Developer Program が要る）
- アプリの中での自動更新
- Homebrew の cask
- `CFBundleVersion` の自動の繰り上げ

## アンチゴール

- 証明書が読めないときに、ad-hoc 署名で DMG を作ってしまう。`build-app.sh` の「ad-hoc 署名に逃げない」をそのまま守る
- 証明書の Secrets が、pull request や `main` への push の workflow から読める
- `.p12` やそのパスワードが、ログ、成果物、ランナーのディスク、リポジトリに残る
- `README.md` に社内のツールの名前が出る（`AGENTS.md` の Internal tool names のとおり、一般的な言い方にする）

## 決めたこと

### Secrets

- 証明書は GitHub の environment `release` の secret に置く。名前は `SIGNING_CERTIFICATE_P12`（`.p12` を base64 にしたもの）と `SIGNING_CERTIFICATE_PASSWORD`
- environment `release` の deployment の規則は、タグ `v*` だけを許す。リポジトリ全体の secret には置かない
- environment `release` とその規則を作り、`.p12` を書き出して Secrets に入れるのは、本人が一度にまとめて行う（キーチェーンの確認に答えるため。作業者の判断: environment も本人が作れば、GitHub への書き込みが 1 か所にまとまる）。手順を `AGENTS.md` に書き、この MR をマージしたあと、次のタグを push する前に済ませる。書き出すのは「Outlook2iCloudCal Developer」の 1 つだけにする（作業者の判断: 書き出し方は作業者が決める。キーチェーンアクセスで 1 つを選んで書き出す方法でもよい）

### CI の job

- `release.yml` の名前は変えない（ruleset が参照している）。今の `release` job のあとに `needs: release` で `dmg` job を足し、`runs-on: macos-26`、`environment: release`、`permissions: contents: write` にする
- 一時的なキーチェーンを作って `.p12` を読み込み、署名が終わったら `if: always()` で消す。`.p12` を書く一時ファイルも同じく消す
- `DEVELOPER_DIR` は `test.yml` と同じく `/Applications/Xcode.app/Contents/Developer`
- 期待する SHA-1 は、リポジトリの中のファイル（たとえば `scripts/signing-certificate-sha1`）に置き、`make dmg` と CI の両方がそれを読む。公開してよい値である（作業者の判断: ファイルの名前と形式は作業者が決める）
- タグの名前と `Info.plist` の版の検査は、今の `release` job の中で `gh release create` より前に行う。違えば Release を作らずに止める（作業者の判断: `dmg` job で止めると、DMG の無い Release が残り、直すにはタグを作り直すことになる）。`dmg` job でも同じ検査をする
- 上げるのは `gh release upload` で行う。同じタグで job をやり直したときのために `--clobber` を付ける
- ランナーで自己署名の証明書を `codesign` が使えるようにする方法（信頼の設定の要否を含む）は作業者が確かめて決める。ad-hoc 署名に逃げないこと、designated requirement を確かめることは変えない

### DMG

- ファイル名は `Outlook2iCloudCal-<version>.dmg`、ボリューム名は `Outlook2iCloudCal`。`hdiutil` の UDZO で作る（作業者の判断）
- `/Applications` へのリンクを置く。`make install` は `~/Applications` に入れるので、すでにそこに入れている人は同じ場所で置き換えるよう、DMG の README と `README.md` に書く。同じ bundle ID のアプリが 2 つあると、ログイン項目がどちらを開くか分からなくなる
- DMG の README には、初回とバージョンを上げるたびに、システム設定 →「プライバシーとセキュリティ」→「このまま開く」か `xattr -dr com.apple.quarantine <app のパス>` が要ることを書く。公証していないので、ブラウザで落とした DMG には毎回 quarantine が付く。許可（カレンダーと通知）は残る

### 文書

- `README.md` の Install: DMG から入れる手順（初回の開き方を含む）を先に書き、ソースからのビルドを「Build from source」として残す。Requirements の Xcode は、ソースからビルドするときだけ要るものにする
- `README.md` から「Releases carry no prebuilt app」の段落を消す。ソースからビルドした版から DMG 版に移ると、証明書が違うので一度だけ許可の出し直しになることを書く
- `AGENTS.md` の Releases: タグで DMG が付くこと、Secrets の名前と environment、証明書を作り直したときは Secrets と期待する SHA-1 の両方を変えること

## 確かめ方

- `make dmg` で DMG ができ、`hdiutil attach` した中の .app で `codesign -d -r-` が期待する SHA-1 を含み、`codesign --verify --deep --strict` が通る
- 期待する SHA-1 を一時的に別の値にすると、`make dmg` が失敗する
- `Info.plist` の版とタグが違う場合の検査は、スクリプトの関数を手元で呼んで確かめる
- CI は次の本物のタグで初めて通る。ランナーの一時的な不具合なら、同じタグの `dmg` job をやり直す（`--clobber` で上げ直せる）。原因がリポジトリの中にあるときは、re-run がタグの時点の workflow とスクリプトを使うので、直したあとで新しいパッチ版のタグを切る。DMG の無い Release は残る（作業者の判断: タグを取る `workflow_dispatch` を足しても、environment の規則でタグの時点のコードしか動かないので、足さない）
- pre-commit（`uvx --with pre-commit-uv==4.3.0 pre-commit@4.6.2 run --all-files`）が通る。actionlint などの workflow の検査がフックにあれば、それも通る

## 作業者に任せること

- `scripts/` のスクリプトの分け方と名前（`build-dmg.sh` など）
- 一時キーチェーンの作り方と、codesign が鍵を使えるようにする手順
- DMG の README の文面（英語）
- 本人が `.p12` を書き出す手順の具体的なコマンド
