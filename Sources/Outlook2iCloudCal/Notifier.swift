import Foundation
import Outlook2iCloudCalCore
import UserNotifications

/// Posts macOS notifications through `UserNotifications`.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let log: SyncLog

    init(log: SyncLog) {
        self.log = log
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [
                .alert, .sound,
            ])
        } catch {
            log.write("notification authorization failed: \(error)")
        }
    }

    func post(_ content: NotificationContent) {
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.body = content.body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: body, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [log] error in
            if let error { log.write("notification failed: \(error)") }
        }
    }

    // Shows banners even while the app is active, since a menu bar app is
    // often the active app when the user has just opened its menu.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
