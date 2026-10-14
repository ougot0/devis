import SwiftUI
import Charts
import DevisCore

/// Statistiques calculées exclusivement à partir des documents enregistrés.
struct StatisticsView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @State private var months = 12
    @State private var report: StatisticsReport?

    var body: some View {
        Group {
            if !purchases.isUnlocked(.statistics) {
                PremiumRequiredView(feature: .statistics)
            } else if let report {
                content(report)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Statistiques")
        .background(Theme.ivory)
        .onAppear(perform: reload)
        .onChange(of: months) { _, _ in reload() }
        .onChange(of: store.revision) { _, _ in reload() }
    }

    private func reload() {
        report = StatisticsEngine.report(records: store.allRecords(), months: months, today: Date())
    }

    private func content(_ report: StatisticsReport) -> some View {
        List {
            Picker("Période", selection: $months) {
                Text("6 mois").tag(6)
                Text("12 mois").tag(12)
                Text("24 mois").tag(24)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Section {
                LabeledContent("Facturé HT") { AmountText(value: report.totalInvoicedHT) }
                LabeledContent("Encaissé") { AmountText(value: report.totalCollected).foregroundStyle(Theme.success) }
                monthlyChart(report.invoicedHTByMonth, title: "Facturé HT par mois", color: Theme.petrol)
                monthlyChart(report.collectedByMonth, title: "Encaissé par mois", color: Theme.ochre)
            } header: {
                Text("Activité")
            } footer: {
                Text("Facturé : factures et acomptes émis, avoirs déduits, à leur date d'émission. Encaissé : paiements enregistrés, à leur date.")
            }

            Section("Devis") {
                LabeledContent("Acceptés", value: "\(report.acceptedQuotes)")
                LabeledContent("Refusés", value: "\(report.refusedQuotes)")
                LabeledContent("Expirés sans réponse", value: "\(report.expiredQuotes)")
                LabeledContent("En attente", value: "\(report.pendingQuotes)")
                if let rate = report.conversionRate {
                    LabeledContent("Taux de transformation") { Text("\(Money.formatQuantity(rate)) %").font(.amount()) }
                } else {
                    Text("Le taux de transformation s'affichera à partir de \(StatisticsEngine.minimumDecidedQuotes) devis acceptés, refusés ou expirés.")
                        .font(.footnote).foregroundStyle(Theme.neutral)
                }
            }

            ranking(report.byCustomer, title: "Répartition par client (HT)")
            ranking(report.topItems, title: "Prestations les plus facturées (HT)")
        }
        .appBackground()
    }

    @ViewBuilder
    private func monthlyChart(_ series: [MonthlyAmount], title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.neutral)
            if series.allSatisfy({ $0.amount == 0 }) {
                Text("Aucune donnée sur la période.").font(.footnote).foregroundStyle(Theme.neutral)
            } else {
                Chart(series) { point in
                    BarMark(x: .value("Mois", point.month, unit: .month), y: .value("Montant", NSDecimalNumber(decimal: point.amount).doubleValue))
                        .foregroundStyle(color)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: months > 12 ? 3 : 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    }
                }
                .frame(height: 150)
                .accessibilityLabel(title)
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }

    @ViewBuilder
    private func ranking(_ items: [RankedAmount], title: String) -> some View {
        Section(title) {
            if items.isEmpty {
                Text("Aucune donnée sur la période.").font(.footnote).foregroundStyle(Theme.neutral)
            }
            let maximum = items.map(\.amount).max() ?? 1
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.label).lineLimit(1)
                        Spacer()
                        AmountText(value: item.amount, weight: .medium)
                    }
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Theme.petrol.opacity(0.7))
                            .frame(width: maximum > 0 ? proxy.size.width * CGFloat(NSDecimalNumber(decimal: max(item.amount, 0) / maximum).doubleValue) : 0, height: 3)
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
