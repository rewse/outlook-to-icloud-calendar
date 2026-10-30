import Foundation
import Testing

@testable import Outlook2iCloudCalCore

/// Noon local time, so the file-name date does not depend on the time zone.
private func localNoon(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SyncLogTests-\(UUID().uuidString)")
}

@Test func writesDailyFile() throws {
    let directory = tempDirectory()
    let log = SyncLog(directory: directory, now: { localNoon(2026, 10, 30) })
    log.write("first line")
    log.write("second line")
    let text = try String(
        contentsOf: directory.appendingPathComponent("2026-10-30.log"), encoding: .utf8)
    let lines = text.split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].hasPrefix("2026-10-30T12:00:00"))
    #expect(lines[0].hasSuffix(" first line"))
    #expect(lines[1].hasSuffix(" second line"))
    #expect(log.directory == directory)
}

@Test func purgeRemovesOlderThan14Days() throws {
    let directory = tempDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for name in ["2026-10-15.log", "2026-10-16.log", "notes.txt", "2026-01-01.txt"] {
        try Data().write(to: directory.appendingPathComponent(name))
    }
    SyncLog(directory: directory, now: { localNoon(2026, 10, 30) }).purge()
    let remaining = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
    #expect(remaining == ["2026-10-16.log", "notes.txt", "2026-01-01.txt"])
}

@Test func purgeWithoutDirectoryDoesNothing() {
    SyncLog(directory: tempDirectory(), now: { localNoon(2026, 10, 30) }).purge()
}
