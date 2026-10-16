import SwiftUI
import DevisCore

/// Aide au micro-entrepreneur : chiffre d'affaires à déclarer, cotisations estimées, plafonds et franchise de TVA.
struct MicroView: View {
    @Environment(AppDataStore.self) private var store
    @State private var settings = MicroSettings()
    @State private var period = DateInterval()
    @State private var records: [DocumentRecord] = []
    @State private var error: PresentedError?

    private var rates: MicroRates { MicroRates.forYear(Calendar.devisMinute.component(.year, from: period.start)) }
    private var isCraftsman: Bool { store.company.registry == .rm }
    private var isMicro: Bool { store.company.legalForm == .microEntrepreneur }

    var body: some View {
        let declaration = MicroCalculator.declaration(records: records, period: period, settings: settings, isCraftsman: isCraftsman)
        List {
            if !isMicro {
                Section {
                    Label("Votre entreprise n'est pas déclarée comme micro-entreprise (Plus › Entreprise et documents). Les chiffres ci-dessous sont donnés à titre indicatif.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(Theme.ochre)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Période précédente")
                        Spacer()
                        Text(declaration.title).font(.headline)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(period.end > Date())
                            .accessibilityLabel("Période suivante")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                    Text("À payer à l'URSSAF (estimation)").font(.subheadline).opacity(0.85).padding(.top, Theme.Space.xs)
                    Text(Money.format(declaration.total))
                        .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Déclaration avant le \(DateFormatting.long(declaration.dueDate)) sur autoentrepreneur.urssaf.fr")
                        .font(.footnote).opacity(0.85)
                }
                .foregroundStyle(.white)
                .card(fill: Theme.petrol)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Ventes de biens") { AmountText(value: declaration.revenue.goods, weight: .regular) }
                LabeledContent("Prestations de services") { AmountText(value: declaration.revenue.services, weight: .regular) }
                LabeledContent("Total à déclarer") { AmountText(value: declaration.revenue.total, style: .headline) }
            } header: {
                Text("Chiffre d'affaires encaissé")
            } footer: {
                Text("Paiements enregistrés sur la période, hors TVA. Biens et services sont séparés selon la nature des lignes de vos factures.")
            }
            Section("Cotisations estimées") {
                if declaration.lines.isEmpty {
                    Text("Aucun encaissement sur la période.").font(.footnote).foregroundStyle(Theme.neutral)
                }
                ForEach(declaration.lines) { line in
                    LabeledContent {
                        AmountText(value: line.amount, weight: .regular)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.label)
                            Text("\(Money.formatQuantity(line.rate)) % de \(Money.format(line.base))").font(.caption).foregroundStyle(Theme.neutral)
                        }
                    }
                }
            }
            Section {
                ForEach(MicroCalculator.thresholds(records: records, year: Calendar.devisMinute.component(.year, from: Date()), franchise: !store.company.isVATRegistered)) { status in
                    ThresholdRow(status: status)
                }
            } header: {
                Text("Plafonds de l'année \(Calendar.devisMinute.component(.year, from: Date()))")
            }
            Section {
                Picker("Prestations", selection: $settings.servicesKind) {
                    ForEach(MicroServicesKind.allCases) { Text($0.label).tag($0) }
                }
                Picker("Déclaration", selection: Binding(get: { settings.frequency }, set: { frequency in
                    settings.frequency = frequency
                    period = MicroCalculator.previousPeriod(before: MicroCalculator.period(containing: Date(), frequency: frequency), frequency: frequency)
                })) {
                    ForEach(DeclarationFrequency.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Versement libératoire de l'impôt", isOn: $settings.versementLiberatoire)
                    .tint(Theme.petrol)
            } header: {
                Text("Votre situation")
            } footer: {
                Text("\(rates.source). Formation professionnelle : \(isCraftsman ? "taux artisan (immatriculation au répertoire des métiers)" : "taux commerçant ou libéral"). Les aides au démarrage (ACRE) ne sont pas prises en compte. Ces montants sont des estimations : seul le calcul de l'URSSAF fait foi.")
            }
        }
        .appBackground()
        .navigationTitle("Cotisations URSSAF")
        .onAppear(perform: load)
        .onChange(of: store.revision) { _, _ in records = store.allRecords() }
        .onChange(of: settings) { _, _ in save() }
        .errorAlert($error)
    }

    private func load() {
        settings = store.company.micro ?? MicroSettings()
        records = store.allRecords()
        // Par défaut, la dernière période terminée : celle qu'il faut déclarer maintenant.
        period = MicroCalculator.previousPeriod(before: MicroCalculator.period(containing: Date(), frequency: settings.frequency), frequency: settings.frequency)
    }

    private func move(_ offset: Int) {
        let calendar = Calendar.devisMinute
        if offset < 0 {
            period = MicroCalculator.previousPeriod(before: period, frequency: settings.frequency, calendar: calendar)
        } else {
            period = MicroCalculator.period(containing: period.end.addingTimeInterval(3600), frequency: settings.frequency, calendar: calendar)
        }
    }

    private func save() {
        guard store.company.micro != settings else { return }
        var profile = store.company
        profile.micro = settings
        do { try store.updateCompany(profile) } catch { self.error = PresentedError(error) }
    }
}

private struct ThresholdRow: View {
    let status: ThresholdStatus

    private var color: Color {
        switch status.level {
        case .ok: return Theme.success
        case .approaching: return Theme.ochre
        case .exceeded, .critical: return Theme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(status.title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Money.format(status.amount)) / \(Money.format(status.limit))").font(.amount(.caption, weight: .regular)).foregroundStyle(Theme.neutral)
            }
            ProgressView(value: min(status.progress, 1))
                .tint(color)
            Text(status.message).font(.caption).foregroundStyle(status.level == .ok ? Theme.neutral : color)
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
