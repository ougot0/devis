import SwiftUI
import SwiftData

@main
struct DevisMinuteApp: App {
    private let container: ModelContainer
    @State private var store: AppDataStore
    @State private var purchases = PurchaseManager()
    @State private var appLock = AppLock()

    init() {
        let container: ModelContainer
        // SwiftData attend que le dossier Application Support existe déjà (absent au tout premier lancement).
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        do {
            #if DEBUG
            if DemoSupport.screen != nil {
                container = try DemoSupport.makeContainer()
            } else {
                container = try ModelContainer(for: SettingsEntity.self, CustomerEntity.self, CatalogEntity.self, DocumentEntity.self)
            }
            #else
            container = try ModelContainer(for: SettingsEntity.self, CustomerEntity.self, CatalogEntity.self, DocumentEntity.self)
            #endif
        } catch {
            // Échec d'ouverture de la base : on ne crée surtout pas une base vide par-dessus.
            fatalError("Impossible d'ouvrir la base de données locale : \(error)")
        }
        self.container = container
        let store = AppDataStore(context: container.mainContext)
        #if DEBUG
        if DemoSupport.screen != nil { DemoSupport.seed(store) }
        #endif
        _store = State(initialValue: store)
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
