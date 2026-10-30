# Repository rules

## Build and test

Run everything through the Makefile.

- `make test` runs the Swift Testing suite. `make test FILTER="A|B"` runs the tests whose names match.
- `make app` builds `build/Outlook2iCloudCal.app` and signs it with the self-signed identity "Outlook2iCloudCal Developer".
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

## Internal tool names

The code may name the internal Outlook MCP server, the certificate command, and their error messages. `README.md` must not: describe them generically (an MCP server that returns Outlook calendar data, the command that renews the authentication certificate).

## Validation

Before committing, stage new files and run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer uvx --with pre-commit-uv==4.3.0 pre-commit@4.6.2 run --all-files`, because `--all-files` skips untracked files. SwiftLint loads sourcekitd from the Xcode toolchain and crashes without `DEVELOPER_DIR`. The SwiftLint hook runs with `--strict`, so warnings fail it too; `.swiftlint.yml` holds the rule settings. CI runs the same hooks in `lint.yml`. `core.hooksPath` points at git-defender, so `pre-commit install` cannot run them at commit time.

## Releases

1. Set `CFBundleShortVersionString` in `Resources/Info.plist` to the new version and commit it.
2. Push a `vX.Y.Z` tag. `release.yml` creates the GitHub Release with notes that git-cliff builds from the Conventional Commits since the previous tag.

The release carries no built app. The signature comes from a certificate on the local Mac, so a CI build would change the signature and revoke the calendar permission. Users build from the tag.

The ruleset `Protect release tags` restricts creating, updating, and deleting `v*` tags to the repository admin role. Never rename `release.yml`.
