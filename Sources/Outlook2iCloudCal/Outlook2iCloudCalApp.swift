import Outlook2iCloudCalCore
import SwiftUI

@main
struct Outlook2iCloudCalApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: StatusIcon.image(for: model.status.badge))
        }
    }
}
