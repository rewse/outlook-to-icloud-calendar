import AppKit
import Outlook2iCloudCalCore
import SwiftUI

/// The menu shown from the menu bar icon, in the order given by the design.
struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let banner = model.status.banner {
            Text(banner)
            if let held = model.heldStoreIDs {
                Button(String(localized: "Delete Held Events…")) { confirmDeletions(held) }
                    .disabled(model.isSyncing)
            }
            Divider()
        }
        Text(String(localized: "Last sync: \(lastSyncText)"))
        Text(String(localized: "Last result: \(countsText)"))
        Divider()
        Button(model.isSyncing ? String(localized: "Syncing…") : String(localized: "Sync Now")) {
            model.sync(.normal, userRequested: true)
        }
            .disabled(model.isSyncing)
        Picker(String(localized: "Sync Interval"), selection: $model.intervalMinutes) {
            ForEach(AppModel.intervalChoices, id: \.self) { minutes in
                Text(Self.intervalLabel(minutes)).tag(minutes)
            }
        }
        Button(String(localized: "Show Log in Finder")) { showLog() }
        Button(String(localized: "Reset and Refetch…")) { confirmReset() }
            .disabled(model.isSyncing)
        Divider()
        Button(String(localized: "Quit")) { NSApp.terminate(nil) }
    }

    private var lastSyncText: String {
        guard let date = model.status.lastSuccessAt else { return String(localized: "None") }
        let format = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return Self.formatter(format).string(from: date)
    }

    private var countsText: String {
        guard let counts = model.status.lastCounts else { return String(localized: "None") }
        let text = String(
            localized: "\(counts.added) added / \(counts.updated) updated / \(counts.deleted) deleted")
        return counts.held > 0 ? text + String(localized: " (\(counts.held) held)") : text
    }

    private static func intervalLabel(_ minutes: Int) -> String {
        minutes < 60
            ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60) hours")
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private func showLog() {
        try? FileManager.default.createDirectory(
            at: model.log.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(model.log.directory)
    }

    private func confirmReset() {
        let window = model.resetWindow
        let format = Self.formatter("M/d")
        // The window end is exclusive, so the last covered day is the day before.
        let lastDay = window.end.addingTimeInterval(-1)
        let first = format.string(from: window.start)
        let last = format.string(from: lastDay)
        if confirm(
            title: String(localized: "Reset and Refetch"),
            message: String(
                localized:
                    "Deletes every Business event from \(first) to \(last) and fetches them again from Outlook."
            ))
        {
            model.sync(.reset, userRequested: true)
        }
    }

    private func confirmDeletions(_ storeIDs: [String]) {
        if confirm(
            title: String(localized: "Delete Held Events"),
            message: String(localized: "Deletes \(storeIDs.count) held events."))
        {
            model.sync(.approveDeletions(Set(storeIDs)), userRequested: true)
        }
    }

    private func confirm(title: String, message: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Run"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
