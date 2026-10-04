import Foundation
import UserNotifications

enum NotificationService {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    static func notifySensitiveContent() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Sensitive content detected"
        content.body = "Choose how to handle it in Copio."
        let request = UNNotificationRequest(identifier: "sensitive-\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }
}
