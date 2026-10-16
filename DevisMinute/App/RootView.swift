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
            if phase == .active { refreshBackgroundServices() }
        }
        .onChange(of: store.revision) { _, _ in refreshBackgroundServices() }
        #if DEBUG
        .onAppear(perform: openDemoScreen)
        .sheet(item: $demoSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .editor(let record): DocumentEditorView(record: record)
                case .detail(let id): DocumentDetailView(documentID: id)
                case .preview(let record): PDFPreviewView(record: record)
                case .statistics: StatisticsView()
                case .signature(let record): SignatureSheet(record: record, initialStrokes: DemoSupport.demoStrokes) {}
                case .reminder(let record): SendDocumentSheet(record: record, mode: .reminder)
                case .expenses: ExpenseListView()
                case .micro: MicroView()
                case .account: AccountView()
                }
            }
        }
        #endif
    }

    #if DEBUG
    enum DemoSheet: Identifiable {
        case editor(DocumentRecord), detail(UUID), preview(DocumentRecord), statistics, signature(DocumentRecord), reminder(DocumentRecord), expenses, micro, account
        var id: String {
            switch self {
            case .signature: return "signature"
            case .reminder: return "reminder"
            case .expenses: return "expenses"
            case .micro: return "micro"
            case .account: return "account"
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
        case .signature:
            selection = .quotes
            if let id = DemoSupport.featuredQuoteID, let record = store.record(id: id) { demoSheet = .signature(record) }
        case .signed:
            selection = .quotes
            if let id = DemoSupport.signedQuoteID { demoSheet = .detail(id) }
        case .expenses:
            selection = .more
            demoSheet = .expenses
        case .micro:
            selection = .more
            demoSheet = .micro
        case .account:
            selection = .more
            demoSheet = .account
        case .reminder:
            selection = .invoices
            if let id = DemoSupport.overdueInvoiceID, let record = store.record(id: id) { demoSheet = .reminder(record) }
        case .signedpdf:
            selection = .quotes
            if let id = DemoSupport.signedQuoteID, let record = store.record(id: id) { demoSheet = .preview(record) }
        }
    }
    #endif

    /// Notifications d'échéance et widgets recalculés après chaque modification.
    private func refreshBackgroundServices() {
        let records = store.allRecords()
        Task { await ReminderScheduler.refresh(records: records) }
        WidgetBridge.publish(store: store, records: records)
    }

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
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AccountManager.self) private var accounts

    var body: some View {
        List {
            Section {
                NavigationLink { AccountView() } label: {
                    HStack(spacing: Theme.Space.m) {
                        InitialsAvatar(name: accounts.account?.name.isEmpty == false ? accounts.account!.name : "Moi", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(accounts.account.map { $0.name.isEmpty ? "Mon compte" : $0.name } ?? "Créer mon compte")
                                .font(.body.weight(.semibold))
                            Text(purchases.isPremium ? "Version complète active" : "Version gratuite · débloquer pour 4,99 €")
                                .font(.footnote).foregroundStyle(purchases.isPremium ? Theme.success : Theme.neutral)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                NavigationLink { CatalogListView() } label: { Label("Catalogue", systemImage: "shippingbox") }
                NavigationLink { premium(.expenses) { ExpenseListView() } } label: { Label("Dépenses et bénéfice", systemImage: "cart") }
                NavigationLink { StatisticsView() } label: { Label("Statistiques", systemImage: "chart.bar") }
                NavigationLink { ProfitabilityView() } label: { Label("Calculateur de rentabilité", systemImage: "percent") }
                NavigationLink { premium(.micro) { MicroView() } } label: { Label("Cotisations URSSAF (micro)", systemImage: "building.columns") }
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

    /// Fonction de la version complète : l'écran, ou la présentation de l'achat.
    @ViewBuilder
    private func premium<Content: View>(_ feature: PremiumFeature, @ViewBuilder content: () -> Content) -> some View {
        if purchases.isUnlocked(feature) { content() } else { PremiumRequiredView(feature: feature) }
    }
}
