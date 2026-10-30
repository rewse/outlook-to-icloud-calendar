# Repository rules

## Build and test

Run everything through the Makefile.

- `make test` runs the Swift Testing suite. `make test FILTER="A|B"` runs the tests whose names match.
- `make app` builds `build/Outlook2iCloudCal.app` and signs it with the self-signed identity "Outlook2iCloudCal Developer".
- `make dmg` runs `make app` and packs the app into `build/Outlook2iCloudCal-<version>.dmg` with its `.sha256`. It stops when the app is not signed by the certificate in `scripts/signing-certificate-sha1`.
- `make install` runs `make app`, copies the app to `~/Applications`, and opens it.
- `make cert` creates the signing identity in the login keychain. It does nothing when the identity exists.

The Makefile and `scripts/build-app.sh` export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. `xcode-select` points at the Command Line Tools, whose SDK lacks the macro plugin that SwiftUI's `@State` needs, and changing `xcode-select` affects other projects. Never run `xcode-select -s`. CI sets the same variable.

Never fall back to ad-hoc signing. The calendar permission is tied to the signature, so an unstable signature asks for permission again after every build.

## Layout

- `Sources/Outlook2iCloudCalCore` holds the logic that tests can reach: parsing, eligibility, the diff and its safety gates, the sync coordinator, logging, and the protocols that abstract EventKit and `mcporter`.
- `Sources/Outlook2iCloudCal` holds the app: the SwiftUI `MenuBarExtra`, the EventKit-backed calendar store, notifications, and the app model.
- Keep the Core target free of UI and EventKit. Put anything that needs them in the app target behind a Core protocol.

## Tests

- Tests never touch the real iCloud calendar, the real Outlook, or the real `mcporter`. Substitute the Core protocols with fakes.
- Fixtures contain invented data only. Never put real subjects, names, companies, locations, or meeting URLs in tests or fixtures.
- Test output must stay free of warnings.

## Localization

- Write user-facing text with `String(localized:)`, using the English text as the key. SwiftUI and AppKit receive the resulting `String`.
- Add every new key to `Resources/Localizable.xcstrings` with a Japanese translation, and to `allKeys` in `Tests/Outlook2iCloudCalCoreTests/LocalizationTests.swift`. Give English a plural variation where the count changes the noun.
- Keep log lines and `SyncOutcome.failed` reasons in English, outside the catalog.
- `scripts/build-app.sh` compiles the catalogs into the app's `en.lproj` and `ja.lproj`. Tests run without them, so `String(localized:)` returns the English key there.

## Internal tool names

The code may name the internal Outlook MCP server, the certificate command, and their error messages. `README.md` must not: describe them generically (an MCP server that returns Outlook calendar data, the command that renews the authentication certificate).

## Validation

Before committing, stage new files and run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer uvx --with pre-commit-uv==4.3.0 pre-commit@4.6.2 run --all-files`, because `--all-files` skips untracked files. SwiftLint loads sourcekitd from the Xcode toolchain and crashes without `DEVELOPER_DIR`. The SwiftLint hook runs with `--strict`, so warnings fail it too; `.swiftlint.yml` holds the rule settings. CI runs the same hooks in `lint.yml`. `core.hooksPath` points at git-defender, so `pre-commit install` cannot run them at commit time.

## Releases

1. Set `CFBundleShortVersionString` in `Resources/Info.plist` to the new version and commit it.
2. Push a `vX.Y.Z` tag. `release.yml` checks the tag against `CFBundleShortVersionString` and stops before creating anything when they differ. It then creates the GitHub Release with notes that git-cliff builds from the Conventional Commits since the previous tag, and its `dmg` job attaches `Outlook2iCloudCal-X.Y.Z.dmg` and its `.sha256`.

The `dmg` job signs with the same "Outlook2iCloudCal Developer" certificate as local builds, so the calendar permission survives switching between a DMG and `make install`. It reads the certificate from the secrets `SIGNING_CERTIFICATE_P12` (the `.p12`, base64) and `SIGNING_CERTIFICATE_PASSWORD` of the environment `release`, which only `v*` tags may deploy to. Only that job uses the environment; the `dmg-smoke` job in `test.yml` runs the same signing path on pull requests with a throwaway certificate and no secrets.

A re-run uses the workflow and scripts at the tag. Re-run a `dmg` job that failed for a runner problem; `--clobber` replaces the files. When the cause is in the repository, fix it and push a new patch tag.

### One-time setup of the release secrets

The repository admin does this once on the Mac that holds the certificate, before the first tag that should carry a DMG. Use `gh` from a host that can reach GitHub.

1. Create the environment and allow only `v*` tags:

   ```sh
   gh api -X PUT repos/rewse/outlook-to-icloud-calendar/environments/release \
     -F 'deployment_branch_policy[protected_branches]=false' \
     -F 'deployment_branch_policy[custom_branch_policies]=true'
   gh api -X POST repos/rewse/outlook-to-icloud-calendar/environments/release/deployment-branch-policies \
     -f name='v*' -f type=tag
   ```

2. Export only this identity. Run `DIR="$(mktemp -d /tmp/o2i-p12.XXXXXX)" && open "$DIR"`. In Keychain Access, open the login keychain, select "Outlook2iCloudCal Developer" under My Certificates, choose File > Export Items, save it as `signing.p12` in that directory, and set a password. (`security export` would export every identity in the keychain.)
3. Store it and its password, then delete the export:

   ```sh
   base64 -i "$DIR/signing.p12" | gh secret set SIGNING_CERTIFICATE_P12 --env release --repo rewse/outlook-to-icloud-calendar
   gh secret set SIGNING_CERTIFICATE_PASSWORD --env release --repo rewse/outlook-to-icloud-calendar
   command rm -rf "$DIR"
   ```

If you ever recreate the certificate, update both secrets and `scripts/signing-certificate-sha1` (`security find-certificate -c "Outlook2iCloudCal Developer" -Z | grep SHA-1`), and expect every Mac to ask for calendar access once more.

The ruleset `Protect release tags` restricts creating, updating, and deleting `v*` tags to the repository admin role. Never rename `release.yml`.
