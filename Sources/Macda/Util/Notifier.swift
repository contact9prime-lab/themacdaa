import Foundation
import UserNotifications

/// Wraps macOS user notifications (banners in Notification Center) for task
/// reminders. Scheduling at the due time means a reminder fires even when Macda
/// isn't focused — and the OS handles it if the app is closed at fire time.
@MainActor
final class Notifier {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()
    private(set) var authorized = false

    func requestAuthorization() {
        center.getNotificationSettings { settings in
            Task { @MainActor in
                if settings.authorizationStatus == .authorized {
                    self.authorized = true
                } else if settings.authorizationStatus == .notDetermined {
                    self.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        Task { @MainActor in
                            self.authorized = granted
                            Log.info("Notifications \(granted ? "granted" : "denied")")
                        }
                    }
                } else {
                    self.authorized = false
                }
            }
        }
    }

    func refreshStatus(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { s in
            Task { @MainActor in
                self.authorized = (s.authorizationStatus == .authorized)
                completion(self.authorized)
            }
        }
    }

    /// Schedule a reminder banner for `id` at `date` (replacing any prior one).
    func scheduleReminder(id: String, title: String, body: String, at date: Date) {
        cancel(id: id)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger: UNNotificationTrigger?
        if date > Date().addingTimeInterval(2) {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func notifyNow(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
