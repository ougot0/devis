import SwiftUI
import UniformTypeIdentifiers
import DevisCore

/// Champ de saisie d'un nombre décimal exact (montant, quantité, taux).
/// Accepte « 12,50 », « 12.5 », « 1 200 ». La valeur n'est mise à jour que si la saisie est valide.
struct DecimalField: View {
    let title: String
    @Binding var value: Decimal
    var suffix: String = ""
    var allowsNegative = false
    var maxScale = Money.unitPriceScale

    @State private var text = ""
    @State private var isInvalid = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.amount(.body, weight: .regular))
                .focused($focused)
                .onChange(of: text) { _, newValue in parse(newValue) }
                .accessibilityLabel(title)
                .accessibilityValue(isInvalid ? "Saisie invalide" : text)
            if !suffix.isEmpty {
                Text(suffix).foregroundStyle(Theme.neutral)
            }
        }
        .foregroundStyle(isInvalid ? Theme.danger : Theme.ink)
        .onAppear { text = Self.display(value) }
        .onChange(of: value) { _, newValue in
            if !focused { text = Self.display(newValue) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                text = Self.display(value)
                isInvalid = false
            }
        }
    }

    private func parse(_ input: String) {
        if input.trimmed.isEmpty {
            value = 0
            isInvalid = false
            return
        }
        guard let parsed = Money.parse(input), allowsNegative || parsed >= 0 else {
            isInvalid = true
            return
        }
        isInvalid = false
        value = Money.round(parsed, scale: maxScale)
    }

    static func display(_ value: Decimal) -> String {
        value == 0 ? "" : Money.formatQuantity(value)
    }
}

/// Ligne libellé + champ, alignée à droite.
struct LabeledDecimalRow: View {
    let label: String
    @Binding var value: Decimal
    var suffix = "€"
    var allowsNegative = false
    var maxScale = Money.unitPriceScale

    var body: some View {
        LabeledContent(label) {
            DecimalField(title: label, value: $value, suffix: suffix, allowsNegative: allowsNegative, maxScale: maxScale)
                .frame(maxWidth: 170)
        }
    }
}

/// Sélecteur de taux de TVA (taux français usuels).
struct VATRatePicker: View {
    @Binding var rate: Decimal

    var body: some View {
        Picker("TVA", selection: $rate) {
            ForEach(VATRates.standard, id: \.self) { value in
                Text("\(Money.formatQuantity(value)) %").tag(value)
            }
            if !VATRates.standard.contains(rate) {
                Text("\(Money.formatQuantity(rate)) %").tag(rate)
            }
        }
    }
}

/// Saisie d'une remise en % ou en €.
struct DiscountEditor: View {
    let title: String
    @Binding var discount: Discount

    private enum Mode: String, CaseIterable { case none = "Aucune", percent = "%", amount = "€" }

    @State private var mode: Mode = .none
    @State private var value: Decimal = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Picker(title, selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if mode != .none {
                LabeledDecimalRow(label: mode == .percent ? "Remise (%)" : "Remise HT", value: $value, suffix: mode == .percent ? "%" : "€", maxScale: 2)
            }
        }
        .onAppear(perform: load)
        .onChange(of: mode) { _, _ in apply() }
        .onChange(of: value) { _, _ in apply() }
    }

    private func load() {
        switch discount {
        case .none: mode = .none; value = 0
        case .percent(let rate): mode = .percent; value = rate
        case .amount(let amount): mode = .amount; value = amount
        }
    }

    private func apply() {
        switch mode {
        case .none: discount = .none
        case .percent: discount = .percent(min(value, 100))
        case .amount: discount = .amount(value)
        }
    }
}

/// Document générique pour `fileExporter`.
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .xml, .pdf, .data] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Erreur présentable dans une alerte.
struct PresentedError: Identifiable {
    let id = UUID()
    let message: String

    init(_ error: Error) {
        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    init(message: String) { self.message = message }
}

extension View {
    func errorAlert(_ error: Binding<PresentedError?>) -> some View {
        alert("Action impossible", isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error.wrappedValue?.message ?? "")
        }
    }
}

/// État vide, sobre et explicatif.
struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "doc"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
