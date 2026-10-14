import SwiftUI
import SwiftData

@main
struct DevisMinuteApp: App {
    private let container: ModelContainer
    @State private var store: DataStore
    @State private var purchases = PurchaseManager()
    @State private var appLock = AppLock()

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: SettingsEntity.self, CustomerEntity.self, CatalogEntity.self, DocumentEntity.self)
        } catch {
            // Échec d'ouverture de la base : on ne crée surtout pas une base vide par-dessus.
            fatalError("Impossible d'ouvrir la base de données locale : \(error)")
        }
        self.container = container
        _store = State(initialValue: DataStore(context: container.mainContext))
        DocumentExportService.purgeTemporaryFiles()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(purchases)
                .environment(appLock)
                .tint(Theme.petrol)
                .task { @MainActor in purchases.start() }
        }
        .modelContainer(container)
    }
}
