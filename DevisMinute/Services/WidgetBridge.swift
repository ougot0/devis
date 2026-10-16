import Foundation
import WidgetKit
import DevisCore

/// Publie le résumé affiché par les widgets dans le conteneur partagé (App Group),
/// puis demande à iOS de les redessiner.
enum WidgetBridge {
    static let appGroup = "group.com.devisminute.app"

    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(WidgetSnapshot.fileName)
    }

    @MainActor
    static func publish(store: AppDataStore, records: [DocumentRecord]) {
        guard let url = snapshotURL else { return }
        let goal = UserDefaults.standard.string(forKey: "monthlyGoalHT").flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        let snapshot = WidgetSnapshot.make(records: records, companyName: store.company.displayName, monthGoal: goal, isPrivate: store.appLockEnabled, today: Date())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Lisible par le widget après le premier déverrouillage de l'iPhone (le widget s'affiche aussi écran verrouillé).
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        WidgetCenter.shared.reloadAllTimelines()
    }
}
