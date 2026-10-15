import Foundation
import SwiftData
import Observation
import DevisCore
import DevisPDF

/// Erreurs remontées à l'interface.
enum StoreError: LocalizedError {
    case notFound
    case issuedDocumentIsImmutable
    case cannotDeleteIssuedDocument
    case complianceBlocking([ComplianceIssue])
    case invoiceNotIssued
    case persistence(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Document introuvable."
        case .issuedDocumentIsImmutable: return "Une facture émise ne peut plus être modifiée. Établissez un avoir pour la corriger."
        case .cannotDeleteIssuedDocument: return "Une facture émise ne peut pas être supprimée : elle doit être conservée. Pour l'annuler, établissez un avoir."
        case .complianceBlocking(let issues):
            return "Informations manquantes avant émission :\n" + issues.filter { $0.severity == .blocking }.map { "• " + $0.message }.joined(separator: "\n")
        case .invoiceNotIssued: return "Cette action nécessite une facture émise."
        case .persistence(let detail): return "Enregistrement impossible : \(detail)"
        case .invalid(let message): return message
        }
    }
}

/// Service de données de l'application : toutes les règles métier passent par DevisCore,
/// cette classe ne fait que les orchestrer et persister le résultat.
@MainActor
@Observable
final class AppDataStore {
    let context: ModelContext
    private let settings: SettingsEntity

    private(set) var company: CompanyProfile
    private(set) var appearance: DocumentAppearance
    private(set) var logoJPEG: Data?
    private(set) var numbering: [String: NumberingState]
    private(set) var schemes: [String: NumberingScheme]
    private(set) var sealHeads: [String: String]
    private(set) var onboardingCompleted: Bool
    private(set) var appLockEnabled: Bool
    /// Incrémenté à chaque modification : permet aux vues calculées (tableau de bord) de se rafraîchir.
    private(set) var revision = 0

    init(context: ModelContext) {
        self.context = context
        let existing = (try? context.fetch(FetchDescriptor<SettingsEntity>()))?.first
        let entity: SettingsEntity
        if let existing {
            entity = existing
        } else {
            entity = SettingsEntity()
            context.insert(entity)
            try? context.save()
        }
        settings = entity
        company = PayloadCoding.decode(CompanyProfile.self, from: entity.profile) ?? CompanyProfile()
        appearance = PayloadCoding.decode(DocumentAppearance.self, from: entity.appearance) ?? DocumentAppearance()
        logoJPEG = entity.logoJPEG
        numbering = PayloadCoding.decode([String: NumberingState].self, from: entity.numbering) ?? [:]
        schemes = PayloadCoding.decode([String: NumberingScheme].self, from: entity.schemes) ?? [:]
        sealHeads = PayloadCoding.decode([String: String].self, from: entity.sealHeads) ?? [:]
        onboardingCompleted = entity.onboardingCompleted
        appLockEnabled = entity.appLockEnabled
    }

    // MARK: - Enregistrement

    private func commit() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            throw StoreError.persistence(error.localizedDescription)
        }
    }

    private func persistSettings() {
        settings.profile = PayloadCoding.encode(company)
        settings.appearance = PayloadCoding.encode(appearance)
        settings.logoJPEG = logoJPEG
        settings.numbering = PayloadCoding.encode(numbering)
        settings.schemes = PayloadCoding.encode(schemes)
        settings.sealHeads = PayloadCoding.encode(sealHeads)
        settings.onboardingCompleted = onboardingCompleted
        settings.appLockEnabled = appLockEnabled
    }

    // MARK: - Réglages

    func updateCompany(_ profile: CompanyProfile) throws {
        company = profile
        persistSettings()
        try commit()
    }

    func completeOnboarding(_ profile: CompanyProfile, appearance newAppearance: DocumentAppearance, logo: Data?) throws {
        company = profile
        appearance = newAppearance
        logoJPEG = logo
        onboardingCompleted = true
        persistSettings()
        try commit()
    }

    func updateAppearance(_ value: DocumentAppearance) throws {
        appearance = value
        persistSettings()
        try commit()
    }

    func updateLogo(_ data: Data?) throws {
        logoJPEG = data
        persistSettings()
        try commit()
    }

    func setAppLock(_ enabled: Bool) throws {
        appLockEnabled = enabled
        persistSettings()
        try commit()
    }

    func scheme(for series: NumberingSeries) -> NumberingScheme {
        schemes[series.rawValue] ?? .default(for: series)
    }

    func state(for series: NumberingSeries) -> NumberingState {
        numbering[series.rawValue] ?? NumberingState()
    }

    func updateScheme(_ scheme: NumberingScheme, for series: NumberingSeries) throws {
        try scheme.validate()
        schemes[series.rawValue] = scheme
        persistSettings()
        try commit()
    }

    func nextNumberPreview(for kind: DocumentKind, date: Date = Date()) -> String {
        let series = NumberingSeries.series(for: kind)
        return NumberingService.preview(scheme: scheme(for: series), state: state(for: series), issueDate: date)
    }

    // MARK: - Lecture

    func allRecords() -> [DocumentRecord] {
        let descriptor = FetchDescriptor<DocumentEntity>(sortBy: [SortDescriptor(\.issueDate, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.record)
    }

    func entity(id: UUID) -> DocumentEntity? {
        var descriptor = FetchDescriptor<DocumentEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func record(id: UUID) -> DocumentRecord? { entity(id: id)?.record }

    func allCustomers(includeArchived: Bool = true) -> [CustomerRecord] {
        let descriptor = FetchDescriptor<CustomerEntity>(sortBy: [SortDescriptor(\.name)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.record).filter { includeArchived || !$0.isArchived }
    }

    func customer(id: UUID) -> CustomerRecord? {
        var descriptor = FetchDescriptor<CustomerEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.record
    }

    func allCatalogItems() -> [CatalogItem] {
        let descriptor = FetchDescriptor<CatalogEntity>(sortBy: [SortDescriptor(\.name)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.item)
    }

    // MARK: - Création de documents

    /// Nouveau devis (non enregistré) pré-rempli avec les réglages de l'entreprise.
    func makeQuote(customer: CustomerRecord?, today: Date = Date()) -> DocumentRecord {
        let calendar = Calendar.devisMinute
        let document = BusinessDocument(
            kind: .quote,
            issueDate: today,
            validUntil: calendar.date(byAdding: .day, value: company.quoteDefaultValidityDays, to: today),
            seller: company,
            customer: customer?.snapshot ?? CustomerSnapshot()
        )
        return DocumentRecord(document: document, quoteStatus: .draft, customerID: customer?.id, createdAt: today, updatedAt: today)
    }

    /// Nouvelle facture indépendante (brouillon, sans numéro).
    func makeInvoice(customer: CustomerRecord?, today: Date = Date()) -> DocumentRecord {
        let calendar = Calendar.devisMinute
        let document = BusinessDocument(
            kind: .invoice,
            issueDate: today,
            serviceDate: today,
            dueDate: calendar.date(byAdding: .day, value: company.paymentTermsDays, to: today),
            seller: company,
            customer: customer?.snapshot ?? CustomerSnapshot(),
            paymentLink: company.defaultPaymentLink
        )
        return DocumentRecord(document: document, invoiceStatus: .draft, customerID: customer?.id, createdAt: today, updatedAt: today)
    }

    /// Enregistre un devis ou une facture brouillon. Refuse toute modification d'une facture émise.
    func save(_ record: DocumentRecord) throws {
        var record = record
        record.updatedAt = Date()
        if let existing = entity(id: record.id) {
            if existing.isIssued, let previous = existing.record, previous.document != record.document {
                throw StoreError.issuedDocumentIsImmutable
            }
            existing.apply(record)
        } else {
            if record.document.kind == .quote && record.document.number.isEmpty {
                // Les devis sont numérotés dès leur premier enregistrement.
                let scheme = scheme(for: .quote)
                var state = state(for: .quote)
                state.lastIssueDate = nil
                let result = try NumberingService.next(scheme: scheme, state: state, issueDate: record.document.issueDate)
                record.document.number = result.number
                numbering[NumberingSeries.quote.rawValue] = result.state
                persistSettings()
            }
            context.insert(DocumentEntity(record: record))
        }
        try commit()
    }

    /// Supprime un brouillon ou un devis. Les factures émises ne peuvent jamais être supprimées.
    func delete(id: UUID) throws {
        guard let entity = entity(id: id) else { throw StoreError.notFound }
        guard !entity.isIssued else { throw StoreError.cannotDeleteIssuedDocument }
        context.delete(entity)
        try commit()
    }

    /// Émission définitive d'une facture, d'une facture d'acompte ou d'un avoir :
    /// contrôle des mentions, numéro chronologique, sceau chaîné, verrouillage.
    @discardableResult
    func issue(id: UUID, now: Date = Date()) throws -> DocumentRecord {
        guard let entity = entity(id: id), var record = entity.record else { throw StoreError.notFound }
        try InvoiceLifecycle.ensureIssuable(record.document, status: record.invoiceStatus ?? .draft)
        // Les coordonnées de l'émetteur sont figées au moment de l'émission.
        record.document.seller = company
        let issues = ComplianceValidator.validate(record.document, today: now)
        guard !ComplianceValidator.hasBlockingIssues(issues) else { throw StoreError.complianceBlocking(issues) }

        let series = NumberingSeries.series(for: record.document.kind)
        let existingNumbers = Set(allRecords().filter { $0.isIssuedInvoice && NumberingSeries.series(for: $0.document.kind) == series }.map(\.document.number))
        let result = try NumberingService.next(scheme: scheme(for: series), state: state(for: series), issueDate: record.document.issueDate, existingNumbers: existingNumbers)
        record.document.number = result.number
        let seal = DocumentSealer.seal(record.document, previousSealHash: sealHeads[series.rawValue] ?? "", sealedAt: now)
        record.seal = seal
        record.invoiceStatus = .issued
        record.issuedAt = now
        record.updatedAt = now

        numbering[series.rawValue] = result.state
        sealHeads[series.rawValue] = seal.sealHash
        persistSettings()
        entity.apply(record)
        try commit()
        return record
    }

    // MARK: - Devis

    func setQuoteStatus(id: UUID, to status: QuoteStatus) throws {
        guard let entity = entity(id: id), var record = entity.record, let current = record.quoteStatus else { throw StoreError.notFound }
        let effective = QuoteLifecycle.effectiveStatus(current, validUntil: record.document.validUntil, today: Date())
        record.quoteStatus = try QuoteLifecycle.transition(from: effective, to: status)
        record.updatedAt = Date()
        entity.apply(record)
        try commit()
    }

    /// Signature du client sur l'iPhone : le devis passe en « Accepté » et son contenu est figé.
    func signQuote(id: UUID, signerName: String, place: String, imageJPEG: Data, signedAt: Date = Date()) throws -> DocumentRecord {
        guard let entity = entity(id: id), var record = entity.record, let current = record.quoteStatus else { throw StoreError.notFound }
        let effective = QuoteLifecycle.effectiveStatus(current, validUntil: record.document.validUntil, today: signedAt)
        guard QuoteLifecycle.canSign(effective) else { throw SignatureError.cannotSign(status: effective.label) }
        // Un brouillon reprend les coordonnées actuelles de l'entreprise, comme sur son aperçu PDF.
        if current == .draft { record.document.seller = company }
        record.signature = try QuoteSignature.make(for: record.document, signerName: signerName, place: place, imageJPEG: imageJPEG, signedAt: signedAt)
        record.quoteStatus = .accepted
        record.updatedAt = signedAt
        entity.apply(record)
        try commit()
        return record
    }

    /// Facture brouillon issue d'un devis ; les factures d'acompte émises sur ce devis sont déduites.
    func convertToInvoice(quoteID: UUID) throws -> DocumentRecord {
        guard let quote = record(id: quoteID), let status = quote.quoteStatus else { throw StoreError.notFound }
        guard QuoteLifecycle.canConvertToInvoice(status) else {
            throw LifecycleError.quoteNotAccepted
        }
        let deposits = allRecords()
            .filter { $0.document.kind == .depositInvoice && $0.isIssuedInvoice && $0.sourceDocumentID == quoteID }
            .sorted { $0.document.issueDate < $1.document.issueDate }
            .map { DepositDeduction(invoiceNumber: $0.document.number, issueDate: $0.document.issueDate, amountTTC: DocumentCalculator.totals(for: $0.document).totalTTC) }
        var invoice = DocumentFactory.invoice(from: quote.document, seller: company, issueDate: Date(), deposits: deposits)
        if invoice.paymentLink == nil { invoice.paymentLink = company.defaultPaymentLink }
        let record = DocumentRecord(document: invoice, invoiceStatus: .draft, customerID: quote.customerID, sourceDocumentID: quoteID)
        if status == .sent { try? setQuoteStatus(id: quoteID, to: .accepted) }
        try save(record)
        return record
    }

    func createDepositInvoice(quoteID: UUID, amountTTC: Decimal) throws -> DocumentRecord {
        guard let quote = record(id: quoteID) else { throw StoreError.notFound }
        var deposit = DocumentFactory.depositInvoice(from: quote.document, seller: company, amountTTC: amountTTC, issueDate: Date())
        if deposit.paymentLink == nil { deposit.paymentLink = company.defaultPaymentLink }
        let record = DocumentRecord(document: deposit, invoiceStatus: .draft, customerID: quote.customerID, sourceDocumentID: quoteID)
        try save(record)
        return record
    }

    func duplicate(id: UUID) throws -> DocumentRecord {
        guard let original = record(id: id) else { throw StoreError.notFound }
        var copy = DocumentFactory.duplicate(original.document, issueDate: Date(), seller: company)
        if copy.kind != .quote { copy.kind = .invoice }
        let record = DocumentRecord(document: copy, customerID: original.customerID)
        try save(record)
        return record
    }

    // MARK: - Factures : paiements et avoirs

    func addPayment(invoiceID: UUID, payment: PaymentRecord) throws {
        guard let entity = entity(id: invoiceID), var record = entity.record else { throw StoreError.notFound }
        guard record.isIssuedInvoice else { throw PaymentError.invoiceNotIssued }
        let ledger = Accounting.ledger(for: record, in: allRecords())
        try ledger.validate(payment.amount)
        var rounded = payment
        rounded.amount = Money.round(payment.amount)
        record.payments.append(rounded)
        record.updatedAt = Date()
        entity.apply(record)
        try commit()
    }

    func removePayment(invoiceID: UUID, paymentID: UUID) throws {
        guard let entity = entity(id: invoiceID), var record = entity.record else { throw StoreError.notFound }
        record.payments.removeAll { $0.id == paymentID }
        record.updatedAt = Date()
        entity.apply(record)
        try commit()
    }

    func createCreditNote(invoiceID: UUID, partialAmountHT: Decimal?, vatRate: Decimal, reason: String) throws -> DocumentRecord {
        guard let invoice = record(id: invoiceID), invoice.isIssuedInvoice, invoice.document.kind != .creditNote else { throw StoreError.invoiceNotIssued }
        let credit: BusinessDocument
        if let partialAmountHT {
            credit = DocumentFactory.partialCreditNote(for: invoice.document, issueDate: Date(), amountHT: partialAmountHT, vatRate: vatRate, reason: reason)
        } else {
            credit = DocumentFactory.fullCreditNote(for: invoice.document, issueDate: Date(), reason: reason)
        }
        var creditDocument = credit
        creditDocument.seller = company
        let record = DocumentRecord(document: creditDocument, invoiceStatus: .draft, customerID: invoice.customerID, sourceDocumentID: invoiceID)
        try save(record)
        return record
    }

    // MARK: - Clients

    func save(customer: CustomerRecord) throws {
        let identifier = customer.id
        var descriptor = FetchDescriptor<CustomerEntity>(predicate: #Predicate { $0.id == identifier })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.apply(customer)
        } else {
            context.insert(CustomerEntity(record: customer))
        }
        try commit()
    }

    /// Supprime un client sans document ; sinon l'archive (les documents gardent ses coordonnées figées).
    func deleteOrArchive(customerID: UUID) throws {
        var descriptor = FetchDescriptor<CustomerEntity>(predicate: #Predicate { $0.id == customerID })
        descriptor.fetchLimit = 1
        guard let entity = try? context.fetch(descriptor).first, var record = entity.record else { throw StoreError.notFound }
        let used = allRecords().contains { $0.customerID == customerID }
        if used {
            record.isArchived = true
            entity.apply(record)
        } else {
            context.delete(entity)
        }
        try commit()
    }

    func importCustomers(_ records: [CustomerRecord]) throws {
        for record in records { context.insert(CustomerEntity(record: record)) }
        try commit()
    }

    // MARK: - Catalogue

    func save(item: CatalogItem) throws {
        let identifier = item.id
        var descriptor = FetchDescriptor<CatalogEntity>(predicate: #Predicate { $0.id == identifier })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.apply(item)
        } else {
            context.insert(CatalogEntity(item: item))
        }
        try commit()
    }

    func deleteCatalogItem(id: UUID) throws {
        var descriptor = FetchDescriptor<CatalogEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entity = try? context.fetch(descriptor).first else { throw StoreError.notFound }
        context.delete(entity)
        try commit()
    }

    func importCatalog(_ items: [CatalogItem]) throws {
        for item in items { context.insert(CatalogEntity(item: item)) }
        try commit()
    }

    // MARK: - Historique et reprise de numérotation

    /// Importe des factures émises avec un autre logiciel (archive, voir `HistoryImporter`).
    func importHistory(_ data: Data) throws -> HistoryImporter.Result {
        let existingNumbers = Set(allRecords().filter { $0.document.kind.isInvoiceLike }.map(\.document.number).filter { !$0.isEmpty })
        let result = HistoryImporter.invoices(data, seller: company, existingCustomers: allCustomers(), existingNumbers: existingNumbers)
        for customer in result.newCustomers { context.insert(CustomerEntity(record: customer)) }
        for record in result.records { context.insert(DocumentEntity(record: record)) }
        try commit()
        return result
    }

    /// Dernier numéro importé qui suit le format de la série, s'il dépasse la numérotation actuelle.
    func suggestedResume(for series: NumberingSeries) -> (number: String, date: Date)? {
        let scheme = scheme(for: series)
        let current = state(for: series)
        let candidates = allRecords()
            .filter { $0.imported && NumberingSeries.series(for: $0.document.kind) == series }
            .compactMap { record -> (Int, String, Date)? in
                guard let sequence = NumberingService.sequence(in: record.document.number, scheme: scheme) else { return nil }
                return (sequence, record.document.number, record.document.issueDate)
            }
            .sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 < $1.2 }
        guard let last = candidates.last else { return nil }
        let currentYear = current.lastYear ?? 0
        let lastYear = Calendar.devisMinute.component(.year, from: last.2)
        if lastYear < currentYear || (lastYear == currentYear && last.0 <= current.lastSequence) { return nil }
        return (last.1, last.2)
    }

    /// Reprend la numérotation après un numéro émis dans un autre logiciel.
    func resumeNumbering(series: NumberingSeries, afterNumber number: String, issuedOn date: Date) throws {
        let scheme = scheme(for: series)
        guard let sequence = NumberingService.sequence(in: number.trimmed, scheme: scheme) else {
            throw StoreError.invalid("Le numéro « \(number) » ne correspond pas au format \(scheme.pattern). Adaptez d'abord le format de numérotation.")
        }
        numbering[series.rawValue] = try NumberingService.resumedState(after: sequence, lastIssueDate: date, lastNumber: number.trimmed, current: state(for: series))
        persistSettings()
        try commit()
    }

    // MARK: - Sauvegarde et restauration

    func makeSnapshot(appVersion: String) -> BackupSnapshot {
        BackupSnapshot(
            appVersion: appVersion,
            company: company,
            customers: allCustomers(),
            catalog: allCatalogItems(),
            documents: allRecords(),
            numbering: numbering,
            numberingSchemes: schemes,
            settings: PayloadCoding.encode(AppSettingsPayload(appearance: appearance, sealHeads: sealHeads, appLockEnabled: appLockEnabled)),
            logo: logoJPEG
        )
    }

    /// Remplace toutes les données par celles de la sauvegarde (après vérification par `BackupService.inspect`).
    func restore(_ snapshot: BackupSnapshot) throws {
        do {
            try context.delete(model: DocumentEntity.self)
            try context.delete(model: CustomerEntity.self)
            try context.delete(model: CatalogEntity.self)
        } catch {
            context.rollback()
            throw StoreError.persistence(error.localizedDescription)
        }
        for customer in snapshot.customers { context.insert(CustomerEntity(record: customer)) }
        for item in snapshot.catalog { context.insert(CatalogEntity(item: item)) }
        for record in snapshot.documents { context.insert(DocumentEntity(record: record)) }
        company = snapshot.company
        numbering = snapshot.numbering
        schemes = snapshot.numberingSchemes
        logoJPEG = snapshot.logo
        if let data = snapshot.settings, let payload = PayloadCoding.decode(AppSettingsPayload.self, from: data) {
            appearance = payload.appearance
            sealHeads = payload.sealHeads
            appLockEnabled = payload.appLockEnabled
        } else {
            sealHeads = Self.rebuildSealHeads(snapshot.documents)
        }
        onboardingCompleted = true
        persistSettings()
        try commit()
    }

    /// Recalcule la tête de chaîne des sceaux de chaque série à partir des documents.
    static func rebuildSealHeads(_ records: [DocumentRecord]) -> [String: String] {
        var heads: [String: String] = [:]
        let issued = records.filter(\.isIssuedInvoice).sorted { ($0.issuedAt ?? $0.document.issueDate) < ($1.issuedAt ?? $1.document.issueDate) }
        for record in issued {
            if let seal = record.seal { heads[NumberingSeries.series(for: record.document.kind).rawValue] = seal.sealHash }
        }
        return heads
    }

    // MARK: - Intégrité

    /// Vérifie la chaîne de sceaux et la continuité de la numérotation de chaque série.
    func integrityReport() -> [String] {
        var problems: [String] = []
        // L'historique importé n'a pas de sceau : il est exclu de la chaîne d'intégrité.
        let records = allRecords().filter { $0.isIssuedInvoice && !$0.imported }
        for series in [NumberingSeries.invoice, .creditNote] {
            let entries = records
                .filter { NumberingSeries.series(for: $0.document.kind) == series }
                .sorted { ($0.issuedAt ?? $0.document.issueDate) < ($1.issuedAt ?? $1.document.issueDate) }
            for problem in SealVerifier.verifyChain(entries.map { ($0.document, $0.seal) }) {
                switch problem {
                case .contentModified(let number): problems.append("Le contenu de \(number) ne correspond plus à son sceau.")
                case .brokenChain(let number): problems.append("Rupture de la chaîne d'intégrité avant \(number) (document manquant ou restauré partiellement).")
                case .missingSeal(let number): problems.append("\(number) n'a pas de sceau d'intégrité.")
                }
            }
        }
        return problems
    }
}

/// Réglages de l'application inclus dans la sauvegarde.
struct AppSettingsPayload: Codable {
    var appearance: DocumentAppearance
    var sealHeads: [String: String]
    var appLockEnabled: Bool
}
