import SwiftUI
import Outlook2iCloudCalCore

@main
struct Outlook2iCloudCalApp: App {
    var body: some Scene {
        MenuBarExtra {
            Button("終了") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "calendar")
        }
    }
}
