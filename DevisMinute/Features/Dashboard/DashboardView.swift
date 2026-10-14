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
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                shortcuts
                Picker("Période", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                figures
                chart
                alerts
                recent
            }
            .padding()
        }
        .background(Theme.ivory)
        .navigationTitle(store.company.displayName.isEmpty ? "Accueil" : store.company.displayName)
        .navigationDestination(for: UUID.self) { DocumentDetailView(documentID: $0) }
        .sheet(item: $editor) { target in
            NavigationStack { DocumentEditorView(record: target.record) }
        }
        .onAppear(perform: reload)
        .onChange(of: store.revision) { _, _ in reload() }
    }

    private func reload() {
        records = store.allRecords()
        customerCount = store.allCustomers(includeArchived: false).count
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
            FigureRow(label: "Reste à encaisser", detail: "\(summary.unpaidInvoicesCount) facture\(summary.unpaidInvoicesCount > 1 ? "s" : "") en attente de paiement", value: summary.outstandingTTC, note: "Toutes périodes")
            Divider()
            FigureRow(label: "En retard", detail: "\(summary.overdueInvoicesCount) facture\(summary.overdueInvoicesCount > 1 ? "s" : "") échue\(summary.overdueInvoicesCount > 1 ? "s" : "")", value: summary.overdueTTC, note: "", emphasis: summary.overdueTTC > 0 ? Theme.danger : nil)
            Divider()
            HStack {
                Text("Clients actifs")
                Spacer()
                Text("\(summary.customerCount)").font(.amount())
            }
            .padding(.vertical, Theme.Space.m)
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
                SectionLabel("Factures en retard")
                ForEach(overdue.prefix(5)) { record in
                    NavigationLink(value: record.id) {
                        let ledger = Accounting.ledger(for: record, in: records)
                        HStack {
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
                    Divider()
                }
            }
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
                Divider()
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
