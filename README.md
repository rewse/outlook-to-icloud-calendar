# Outlook2iCloudCal

A macOS menu bar app that copies events from an Outlook calendar into an iCloud calendar named `Business`, so work events show up on personal devices. Sync runs in one direction, from Outlook to iCloud.

## How it syncs

The app fetches events from one month back to six months ahead, hourly by default. The interval is 15 minutes, 30 minutes, 1 hour, or 3 hours, chosen from the menu. It copies four fields: start, end, subject, and location.

An event is copied only when all of these hold:

- You accepted it or organize it.
- It is not canceled, and its subject does not start with `Canceled:` or `Declined:`.
- It is not an all-day event.

Declined, tentative, and unanswered events are skipped, and so are responses the app does not recognize. The log records the reason for each skipped event.

Each sync adds new events, updates changed ones, and deletes events that are gone from Outlook. The app only touches events it created in `Business`. Events you add there by hand are left alone, and so is anything older than one month.

## Safety checks

- Incomplete fetch: The fetched range is split into seven monthly segments. If the fetch for any segment returns nothing, or any segment ends up with no events, the fetch is assumed to be cut short and the whole sync is discarded without writing anything.
- Mass deletion: If a sync would delete at least 5 events and at least 10% of the events the app manages, the deletions are held back while additions and updates go through. The hold is recomputed on every sync. Held deletions run only after you choose 削除を実行… (Run deletions) from the menu, and only the events that were held at that moment are deleted. If the next fetch would delete more, the extra deletions go through this check again.
- Failed fetch: If the fetch fails, nothing is written. A lapsed authentication certificate is the usual cause in the morning. The icon shows a red mark and no dialog appears.

Other problems also raise a macOS notification, once per change of state, so a persistent problem does not notify every hour. A lapsed certificate does not notify.

Logs are written to `~/Library/Logs/Outlook2iCloudCal/`, one file per day, and files older than 14 days are removed. They include event subjects and stay on your Mac.

## Menu

The icon is a template image that follows light and dark mode. A red "!" marks a lapsed certificate, a discarded sync, or any other failed sync, and an orange pause mark means deletions are on hold. The menu is in Japanese and shows, from the top:

1. A notice when something needs attention, with 削除を実行… (Run deletions) while deletions are on hold
2. 最終同期: the time of the last sync
3. 直前の同期: the counts from the last sync
4. 今すぐ同期 (Sync now)
5. 自動同期の間隔 (Sync interval)
6. ログを Finder で表示 (Show log in Finder)
7. 初期化して再取得… (Reset and refetch)
8. 終了 (Quit)

Sync now, Run deletions, and Reset and refetch are disabled while a sync is running.

Reset and refetch asks for confirmation, then deletes everything in `Business` within the range, including events the app did not create, and fetches again. Recurring events are left alone, since the app never creates them. It replaces the events only after a fetch has succeeded and passed the completeness check, so running it with a lapsed certificate leaves `Business` untouched.

## Requirements

- macOS 15 or later
- Xcode, installed at `/Applications/Xcode.app`. The build sets `DEVELOPER_DIR` itself, so `xcode-select` can keep pointing at the Command Line Tools.
- `mcporter` with an MCP server registered that returns your Outlook calendar
- The command that renews the certificate the MCP server needs for authentication
- An iCloud account signed in to the macOS Calendar app

## Install

```sh
git clone https://github.com/rewse/outlook-to-icloud-calendar.git
cd outlook-to-icloud-calendar
git checkout vX.Y.Z   # a release tag
make cert && make install
```

`make cert` creates a self-signed code-signing certificate in your login keychain. The app is signed with it because the calendar permission is tied to the signature, and an unstable signature would ask again after every build. `make install` builds the app, copies it to `~/Applications`, and opens it. Allow calendar access and notifications when macOS asks. On first launch the app registers itself as a login item, so it starts again when you log in; you can turn this off in System Settings under General > Login Items.

Releases carry no prebuilt app, for the same reason: a build signed elsewhere has a different signature.

## Development

```sh
make test
make app
```

Tests use fakes for EventKit and `mcporter` and never touch a real calendar.

## License

MIT. See [LICENSE](LICENSE).
