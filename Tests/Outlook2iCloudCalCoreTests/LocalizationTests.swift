import Foundation
import Testing

/// Every key the code passes to `String(localized:)`, in the form the
/// interpolations produce (Int as `%lld`, String as `%@`).
private let allKeys = [
    "Certificate expired. Run mwinit.",
    "Fetch was incomplete. Sync skipped.",
    "%lld deletions on hold (%lld%% of %lld managed)",
    "Sync failed. Check the log.",
    "Delete Held Events…",
    "Last sync: %@",
    "Last result: %@",
    "%lld added / %lld updated / %lld deleted",
    " (%lld held)",
    "None",
    "Sync Now",
    "Syncing…",
    "Sync Interval",
    "%lld min",
    "%lld hours",
    "Show Log in Finder",
    "Reset and Refetch…",
    "Quit",
    "Reset and Refetch",
    "Deletes every Business event from %@ to %@ and fetches them again from Outlook.",
    "Delete Held Events",
    "Deletes %lld held events.",
    "Run",
    "Cancel",
]

private let catalogURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../../Resources/Localizable.xcstrings")
    .standardized

private func catalogStrings() throws -> [String: [String: Any]] {
    let data = try Data(contentsOf: catalogURL)
    let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(root["sourceLanguage"] as? String == "en")
    return try #require(root["strings"] as? [String: [String: Any]])
}

/// True when `localization` is translated, either as one string or as variations.
private func isTranslated(_ localization: [String: Any]?) -> Bool {
    guard let localization else { return false }
    if let unit = localization["stringUnit"] as? [String: Any] {
        return unit["state"] as? String == "translated"
    }
    return localization["variations"] != nil
}

@Test func everyKeyHasJapanese() throws {
    let strings = try catalogStrings()
    for key in allKeys {
        let localizations = strings[key]?["localizations"] as? [String: [String: Any]]
        #expect(isTranslated(localizations?["ja"]), "missing ja for \(key)")
    }
}

@Test func catalogHasNoUnusedKeys() throws {
    #expect(Set(try catalogStrings().keys) == Set(allKeys))
}

/// Compiles the catalog and formats keys the way the app does at run time.
struct CompiledCatalogTests {
    let english: Bundle
    let japanese: Bundle

    init() throws {
        let output = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xcstringstool", "compile", catalogURL.path, "--output-directory", output.path,
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        english = try #require(Bundle(path: output.appending(path: "en.lproj").path))
        japanese = try #require(Bundle(path: output.appending(path: "ja.lproj").path))
    }

    private func render(_ bundle: Bundle, _ key: String, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        return String(format: format, locale: Locale(identifier: "en_US_POSIX"), arguments: arguments)
    }

    @Test func hoursUsePluralForms() {
        #expect(render(english, "%lld hours", 1) == "1 hour")
        #expect(render(english, "%lld hours", 3) == "3 hours")
        #expect(render(japanese, "%lld hours", 3) == "3 時間")
    }

    @Test func heldBannerUsesPluralFormsAndJapaneseOrder() {
        let key = "%lld deletions on hold (%lld%% of %lld managed)"
        #expect(render(english, key, 1, 13, 8) == "1 deletion on hold (13% of 8 managed)")
        #expect(render(english, key, 42, 23, 180) == "42 deletions on hold (23% of 180 managed)")
        #expect(render(japanese, key, 42, 23, 180) == "削除 42 件を保留中（管理中 180 件の 23%）")
    }

    @Test func deletionConfirmUsesPluralForms() {
        #expect(render(english, "Deletes %lld held events.", 1) == "Deletes 1 held event.")
        #expect(render(english, "Deletes %lld held events.", 6) == "Deletes 6 held events.")
    }

    @Test func resetMessageKeepsDateOrderInJapanese() {
        let key = "Deletes every Business event from %@ to %@ and fetches them again from Outlook."
        #expect(
            render(japanese, key, "9/30", "4/29")
                == "範囲内（9/30〜4/29）の Business の予定をすべて削除して、Outlook から取り直します。")
        #expect(render(japanese, "Last result: %@", "x") == "直前の同期：x")
    }
}
