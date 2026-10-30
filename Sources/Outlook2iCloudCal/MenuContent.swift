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
                Button("削除を実行…") { confirmDeletions(held) }
            }
            Divider()
        }
        Text("最終同期：\(lastSyncText)")
        Text("直前の同期：\(countsText)")
        Divider()
        Button(model.isSyncing ? "同期中…" : "今すぐ同期") { model.sync(.normal) }
            .disabled(model.isSyncing)
        Picker("自動同期の間隔", selection: $model.intervalMinutes) {
            ForEach(AppModel.intervalChoices, id: \.self) { minutes in
                Text(Self.intervalLabel(minutes)).tag(minutes)
            }
        }
        Button("ログを Finder で表示") { showLog() }
        Button("初期化して再取得…") { confirmReset() }
            .disabled(model.isSyncing)
        Divider()
        Button("終了") { NSApp.terminate(nil) }
    }

    private var lastSyncText: String {
        guard let date = model.status.lastSuccessAt else { return "なし" }
        let format = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return Self.formatter(format).string(from: date)
    }

    private var countsText: String {
        guard let counts = model.status.lastCounts else { return "なし" }
        let text = "追加 \(counts.added) / 更新 \(counts.updated) / 削除 \(counts.deleted)"
        return counts.held > 0 ? text + "（保留 \(counts.held)）" : text
    }

    private static func intervalLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) 分" : "\(minutes / 60) 時間"
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
        let span = "\(format.string(from: window.start))〜\(format.string(from: lastDay))"
        if confirm(
            title: "初期化して再取得",
            message: "範囲内（\(span)）の Business の予定をすべて削除して、Outlook から取り直します。")
        {
            model.sync(.reset)
        }
    }

    private func confirmDeletions(_ storeIDs: [String]) {
        if confirm(title: "削除を実行", message: "保留中の削除 \(storeIDs.count) 件を実行します。") {
            model.sync(.approveDeletions(Set(storeIDs)))
        }
    }

    private func confirm(title: String, message: String) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "実行")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
