import Foundation
import UserNotifications
import DevisCore

/// Notifications locales d'échéance : programmées sur l'iPhone, sans serveur.
/// Elles sont recalculées à chaque modification des données (paiement, émission…).
@MainActor
enum ReminderScheduler {
    static let enabledKey = "dueRemindersEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Demande l'autorisation ; retourne vrai si les notifications sont permises.
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        return granted
    }

    static func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        await removeAll()
    }

    static func refresh(records: [DocumentRecord], now: Date = Date()) async {
        await removeAll()
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.devisMinute
        for alert in ReminderPolicy.alerts(for: records, now: now) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.userInfo = ["documentID": alert.documentID.uuidString]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: alert.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: trigger))
        }
    }

    private static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPolicy.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
