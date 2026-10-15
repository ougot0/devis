import SwiftUI
import DevisCore

/// Racine : assistant de configuration au premier lancement, puis navigation par onglets.
struct RootView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    #if DEBUG
    @State private var demoSheet: DemoSheet?
    #endif

    enum AppTab: Hashable { case home, quotes, invoices, customers, more }

    var body: some View {
        Group {
            if !store.onboardingCompleted {
                OnboardingView()
            } else if store.appLockEnabled && !appLock.isUnlocked {
                LockedView()
            } else {
                tabs
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && store.appLockEnabled { appLock.lock() }
        }
        #if DEBUG
        .onAppear(perform: openDemoScreen)
        .sheet(item: $demoSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .editor(let record): DocumentEditorView(record: record)
                case .detail(let id): DocumentDetailView(documentID: id)
                case .preview(let record): PDFPreviewView(record: record)
                case .statistics: StatisticsView()
                }
            }
        }
        #endif
    }

    #if DEBUG
    enum DemoSheet: Identifiable {
        case editor(DocumentRecord), detail(UUID), preview(DocumentRecord), statistics
        var id: String {
            switch self {
            case .editor: return "editor"
            case .detail: return "detail"
            case .preview: return "preview"
            case .statistics: return "statistics"
            }
        }
    }

    /// Mode démonstration (captures d'écran) : ouvre directement l'écran demandé.
    private func openDemoScreen() {
        guard let screen = DemoSupport.screen else { return }
        switch screen {
        case .onboarding, .dashboard: selection = .home
        case .quotes: selection = .quotes
        case .invoices: selection = .invoices
        case .customers: selection = .customers
        case .more: selection = .more
        case .statistics:
            selection = .more
            demoSheet = .statistics
        case .editor:
            selection = .quotes
            if let id = DemoSupport.featuredQuoteID, let record = store.record(id: id) { demoSheet = .editor(record) }
        case .detail:
            selection = .invoices
            if let id = DemoSupport.featuredInvoiceID { demoSheet = .detail(id) }
        case .preview:
            selection = .quotes
            if let id = DemoSupport.featuredQuoteID, let record = store.record(id: id) { demoSheet = .preview(record) }
        }
    }
    #endif

    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardView(selection: $selection) }
                .tabItem { Label("Accueil", systemImage: "house") }
                .tag(AppTab.home)
            NavigationStack { DocumentListView(group: .quotes) }
                .tabItem { Label("Devis", systemImage: "doc.text") }
                .tag(AppTab.quotes)
            NavigationStack { DocumentListView(group: .invoices) }
                .tabItem { Label("Factures", systemImage: "doc.plaintext") }
                .tag(AppTab.invoices)
            NavigationStack { CustomerListView() }
                .tabItem { Label("Clients", systemImage: "person.2") }
                .tag(AppTab.customers)
            NavigationStack { MoreView() }
                .tabItem { Label("Plus", systemImage: "ellipsis.circle") }
                .tag(AppTab.more)
        }
    }
}

/// Écran affiché tant que l'application est verrouillée.
struct LockedView: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            Image(systemName: "lock")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.petrol)
            Text("DevisMinute est verrouillé")
                .font(.title3.weight(.semibold))
            if let message = appLock.errorMessage {
                Text(message).font(.footnote).foregroundStyle(Theme.neutral).multilineTextAlignment(.center)
            }
            Button("Déverrouiller avec \(appLock.biometryLabel)") {
                Task { await appLock.unlock() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.Space.xxl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ivory)
        .task { await appLock.unlock() }
    }
}

/// Onglet « Plus » : outils et réglages.
struct MoreView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { CatalogListView() } label: { Label("Catalogue", systemImage: "shippingbox") }
                NavigationLink { StatisticsView() } label: { Label("Statistiques", systemImage: "chart.bar") }
                NavigationLink { ProfitabilityView() } label: { Label("Calculateur de rentabilité", systemImage: "percent") }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Entreprise et documents", systemImage: "building.2") }
                NavigationLink { BackupView() } label: { Label("Sauvegarde, import et export", systemImage: "externaldrive") }
                NavigationLink { IntegrityView() } label: { Label("Intégrité des factures", systemImage: "checkmark.seal") }
            }
            Section {
                NavigationLink { ComplianceInfoView() } label: { Label("Conformité et limites", systemImage: "info.circle") }
                NavigationLink { PremiumView() } label: { Label("Version complète", systemImage: "star") }
            }
        }
        .navigationTitle("Plus")
        .appBackground()
    }
}
