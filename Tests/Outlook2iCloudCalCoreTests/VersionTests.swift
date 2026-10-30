import Testing
@testable import Outlook2iCloudCalCore

@Test func appInfoNames() {
    #expect(AppInfo.name == "Outlook2iCloudCal")
    #expect(AppInfo.bundleID == "io.github.rewse.Outlook2iCloudCal")
}
