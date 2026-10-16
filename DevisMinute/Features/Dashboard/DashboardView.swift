import SwiftUI
import Charts
import DevisCore

/// Tableau de bord : distingue clairement devis en attente, montants facturés et sommes encaissées.
struct DashboardView: View {
    @Environment(AppDataStore.self) private var store
    @Binding var selection: RootView.AppTab

    @State private var records: [DocumentRecord] = []
    @State private var customerCount = 0
    @State private var period: Period = .year
    @State private var editor: EditorTarget?
    @State private var editingGoal = false
    @State private var ringProgress: Double = 0
    /// Objectif de chiffre d'affaires mensuel (HT), propre à cet iPhone.
    @AppStorage("monthlyGoalHT") private var goalText = ""

    enum Period: String, CaseIterable, Identifiable {
        case month = "Ce mois-ci"
        case year = "Cette année"
        case all = "Depuis le début"
        var id: String { rawValue }

        func interval(today: Date) -> DateInterval? {
            let calendar = Calendar.devisMinute
            switch self {
            case .month: return calendar.dateInterval(of: .month, for: today)
            case .year: return calendar.dateInterval(of: .year, for: today)
            case .all: return nil
            }
        }
    }

    struct EditorTarget: Identifiable {
        let id = UUID()
        let record: DocumentRecord
    }

    private var today: Date { Date() }

    private var summary: DashboardSummary {
        StatisticsEngine.dashboard(records: records, customerCount: customerCount, period: period.interval(today: today), today: today)
    }

    private var report: StatisticsReport {
        StatisticsEngine.report(records: records, months: 6, today: today)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                greeting
                outstandingCard
                goalCard
                shortcuts
                    .padding(.vertical, Theme.Space.xs)
                Picker("Période", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                figures.card()
                chart.card()
                alerts
                recent.card()
            }
            .padding()
        }
        .background(Theme.ivory)
        .navigationTitle("Accueil")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editingGoal) {
            NavigationStack { GoalEditor(goalText: $goalText) }
                .presentationDetents([.medium])
        }
        .navigationDestination(for: UUID.self) { DocumentDetailView(documentID: $0) }
        .sheet(item: $editor) { target in
            NavigationStack { DocumentEditorView(record: target.record) }
        }
        .onAppear(perform: reload)
        .onChange(of: store.revision) { _, _ in reload() }
        .onChange(of: goalText) { _, _ in reload() }
    }

    private func reload() {
        records = store.allRecords()
        customerCount = store.allCustomers(includeArchived: false).count
        withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) {
            ringProgress = goalProgress
        }
    }

    // MARK: En-tête et cartes principales

    private var firstName: String {
        let owner = store.company.ownerName.trimmed
        if let first = owner.split(separator: " ").first { return String(first) }
        return store.company.displayName
    }

    private var greeting: some View {
        let hour = Calendar.current.component(.hour, from: today)
        let hello = (5..<18).contains(hour) ? "Bonjour" : "Bonsoir"
        return VStack(alignment: .leading, spacing: 2) {
            Text(today.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR"))).capitalized(with: Locale(identifier: "fr_FR")))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.neutral)
            Text(firstName.isEmpty ? hello : "\(hello) \(firstName)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.top, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    /// Grande carte pétrole : ce qui reste à encaisser, toutes périodes confondues.
    private var outstandingCard: some View {
        let summary = StatisticsEngine.dashboard(records: records, customerCount: customerCount, period: nil, today: today)
        return Button { selection = .invoices } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Label("À encaisser", systemImage: "eurosign.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.7)
                }
                Text(Money.format(summary.outstandingTTC))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: summary.outstandingTTC).doubleValue))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Theme.Space.s) {
                    Text(summary.unpaidInvoicesCount == 0 ? "Tout est encaissé" : "\(summary.unpaidInvoicesCount) facture\(summary.unpaidInvoicesCount > 1 ? "s" : "") en attente")
                        .font(.footnote)
                        .opacity(0.85)
                    if summary.overdueInvoicesCount > 0 {
                        Text("\(Money.format(summary.overdueTTC)) en retard")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(red: 0.93, green: 0.55, blue: 0.42).opacity(0.95), in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .foregroundStyle(.white)
            .card(fill: Theme.petrol)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre la liste des factures")
    }

    private var goal: Decimal? {
        guard let value = Decimal(string: goalText, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    /// Facturé HT ce mois-ci (factures émises, avoirs déduits).
    private var monthInvoicedHT: Decimal {
        guard let month = Calendar.devisMinute.dateInterval(of: .month, for: today) else { return 0 }
        return records
            .filter { $0.isIssuedInvoice && month.contains($0.document.issueDate) }
            .reduce(Decimal(0)) { $0 + Accounting.invoicedHT($1) }
    }

    private var goalProgress: Double {
        guard let goal else { return 0 }
        return max(0, NSDecimalNumber(decimal: monthInvoicedHT / goal).doubleValue)
    }

    private var goalCard: some View {
        let invoiced = monthInvoicedHT
        let monthName = today.formatted(.dateTime.month(.wide).locale(Locale(identifier: "fr_FR")))
        return Button { editingGoal = true } label: {
            HStack(spacing: Theme.Space.l) {
                ZStack {
                    Circle().stroke(Theme.petrol.opacity(0.12), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(ringProgress, 1))
                        .stroke(ringProgress >= 1 ? Theme.ochre : Theme.petrol, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if goal != nil {
                        Text("\(Int((goalProgress * 100).rounded())) %")
                            .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.ink)
                    } else {
                        Image(systemName: "target").font(.title3).foregroundStyle(Theme.petrol)
                    }
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Objectif de \(monthName)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    if let goal {
                        Text("\(Money.format(invoiced)) facturés HT sur \(Money.format(goal))")
                            .font(.footnote).foregroundStyle(Theme.neutral)
                        Text(goalProgress >= 1 ? "Objectif atteint, bravo !" : "Encore \(Money.format(max(goal - invoiced, 0))) à facturer")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(goalProgress >= 1 ? Theme.ochre : Theme.petrol)
                    } else {
                        Text("Fixez-vous un chiffre d'affaires à atteindre ce mois-ci et suivez votre progression.")
                            .font(.footnote).foregroundStyle(Theme.neutral)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Modifier l'objectif mensuel")
    }

    // MARK: Sections

    private var shortcuts: some View {
        HStack(spacing: Theme.Space.s) {
            Button { editor = EditorTarget(record: store.makeQuote(customer: nil)) } label: {
                Label("Devis", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button { editor = EditorTarget(record: store.makeInvoice(customer: nil)) } label: {
                Label("Facture", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            NavigationLink { CustomerEditorView(customer: nil) } label: {
                Label("Client", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var figures: some View {
        let summary = summary
        return VStack(spacing: 0) {
            FigureRow(label: "Devis en attente de réponse", detail: "\(summary.pendingQuotesCount) devis envoyé\(summary.pendingQuotesCount > 1 ? "s" : "")", value: summary.pendingQuotesTTC, note: "Non facturé")
            Divider()
            FigureRow(label: "Facturé", detail: "Factures émises, avoirs déduits (TTC)", value: summary.invoicedTTC, note: period.rawValue)
            Divider()
            FigureRow(label: "Encaissé", detail: "Paiements que vous avez enregistrés", value: summary.collectedTTC, note: period.rawValue, emphasis: Theme.success)
            Divider()
            let profit = store.profit(interval: period.interval(today: today))
            if profit.expenses > 0 {
                FigureRow(label: "Dépenses", detail: "Achats et frais saisis (\(store.company.isVATRegistered ? "HT" : "TTC"))", value: profit.expenses, note: period.rawValue)
                Divider()
                FigureRow(label: "Bénéfice estimé", detail: "Facturé HT moins les dépenses", value: profit.profit, note: period.rawValue, emphasis: profit.profit < 0 ? Theme.danger : Theme.success)
                Divider()
            }
            FigureRow(label: "Reste à encaisser", detail: "\(summary.unpaidInvoicesCount) facture\(summary.unpaidInvoicesCount > 1 ? "s" : "") en attente de paiement", value: summary.outstandingTTC, note: "Toutes périodes")
            Divider()
            FigureRow(label: "En retard", detail: "\(summary.overdueInvoicesCount) facture\(summary.overdueInvoicesCount > 1 ? "s" : "") échue\(summary.overdueInvoicesCount > 1 ? "s" : "")", value: summary.overdueTTC, note: "", emphasis: summary.overdueTTC > 0 ? Theme.danger : nil)
            Divider()
            HStack {
                Text("Clients actifs")
                Spacer()
                Text("\(summary.customerCount)").font(.amount())
            }
            .padding(.top, Theme.Space.m)
        }
    }

    private var chart: some View {
        let report = report
        let hasData = report.invoicedHTByMonth.contains { $0.amount != 0 } || report.collectedByMonth.contains { $0.amount != 0 }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("6 derniers mois — facturé HT et encaissé")
            if hasData {
                Chart {
                    ForEach(report.invoicedHTByMonth) { point in
                        BarMark(x: .value("Mois", point.month, unit: .month), y: .value("Montant", NSDecimalNumber(decimal: point.amount).doubleValue))
                            .foregroundStyle(by: .value("Série", "Facturé HT"))
                            .position(by: .value("Série", "Facturé HT"))
                    }
                    ForEach(report.collectedByMonth) { point in
                        BarMark(x: .value("Mois", point.month, unit: .month), y: .value("Montant", NSDecimalNumber(decimal: point.amount).doubleValue))
                            .foregroundStyle(by: .value("Série", "Encaissé"))
                            .position(by: .value("Série", "Encaissé"))
                    }
                }
                .chartForegroundStyleScale(["Facturé HT": Theme.petrol, "Encaissé": Theme.ochre])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Graphique du montant facturé et encaissé par mois")
            } else {
                Text("Le graphique apparaîtra dès votre première facture émise.")
                    .font(.footnote)
                    .foregroundStyle(Theme.neutral)
                    .padding(.vertical, Theme.Space.l)
            }
        }
    }

    @ViewBuilder
    private var alerts: some View {
        let overdue = records.filter { record in
            guard record.isIssuedInvoice, record.document.kind != .creditNote else { return false }
            return Accounting.ledger(for: record, in: records).state(dueDate: record.document.dueDate, today: today) == .overdue
        }
        if !overdue.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label("Factures en retard", systemImage: "exclamationmark.triangle.fill")
                    .font(.sectionLabel).foregroundStyle(Theme.danger)
                ForEach(overdue.prefix(5)) { record in
                    NavigationLink(value: record.id) {
                        let ledger = Accounting.ledger(for: record, in: records)
                        HStack(spacing: Theme.Space.m) {
                            InitialsAvatar(name: record.document.customer.name, size: 34)
                            VStack(alignment: .leading) {
                                Text(record.document.customer.name).foregroundStyle(Theme.ink)
                                Text("\(record.document.number) · \(ledger.daysOverdue(dueDate: record.document.dueDate, today: today)) j de retard")
                                    .font(.footnote).foregroundStyle(Theme.danger)
                            }
                            Spacer()
                            AmountText(value: ledger.balance)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                    if record.id != overdue.prefix(5).last?.id { Divider() }
                }
            }
            .card(fill: Theme.danger.opacity(0.07))
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionLabel("Activité récente")
            let recentRecords = records.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)
            if recentRecords.isEmpty {
                Text("Aucun document pour l'instant. Créez votre premier devis : comptez moins de deux minutes.")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
            ForEach(Array(recentRecords)) { record in
                NavigationLink(value: record.id) {
                    DocumentRow(record: record, allRecords: records)
                }
                .buttonStyle(.plain)
                if record.id != recentRecords.last?.id { Divider() }
            }
        }
    }
}

/// Ligne d'indicateur : libellé, explication, montant.
private struct FigureRow: View {
    let label: String
    let detail: String
    let value: Decimal
    let note: String
    var emphasis: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(Theme.neutral)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: value, style: .title3)
                    .foregroundStyle(emphasis ?? Theme.ink)
                if !note.isEmpty { Text(note).font(.caption2).foregroundStyle(Theme.neutral) }
            }
        }
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .combine)
    }
}

/// Saisie de l'objectif mensuel.
private struct GoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var goalText: String
    @State private var value: Decimal = 0

    var body: some View {
        Form {
            Section {
                LabeledDecimalRow(label: "Chiffre d'affaires HT", value: $value, maxScale: 0)
            } footer: {
                Text("Montant HT à facturer chaque mois. L'anneau de l'accueil se remplit avec les factures émises dans le mois, avoirs déduits.")
            }
            if !goalText.isEmpty {
                Section {
                    Button("Supprimer l'objectif", role: .destructive) {
                        goalText = ""
                        dismiss()
                    }
                }
            }
        }
        .appBackground()
        .navigationTitle("Objectif mensuel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    goalText = value > 0 ? NSDecimalNumber(decimal: value).stringValue : ""
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            value = Decimal(string: goalText, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        }
    }
}
