import SwiftUI
import DevisCore

/// Sections de formulaire du profil d'entreprise, partagées entre l'assistant et les réglages.
struct LegalStatusSection: View {
    @Binding var profile: CompanyProfile

    var body: some View {
        Section {
            // Libellés longs : liste complète plutôt qu'un menu qui les tronque.
            Picker("Forme juridique", selection: $profile.legalForm) {
                ForEach(LegalForm.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.navigationLink)
            Picker("TVA", selection: $profile.vatRegime) {
                ForEach(VATRegime.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            if profile.vatRegime == .standard {
                Toggle("Option pour la TVA sur les débits", isOn: $profile.vatOnDebits)
            }
        } header: {
            Text("Statut")
        } footer: {
            Text(statusHelp)
        }
    }

    private var statusHelp: String {
        var text = ""
        if profile.legalForm.isIndividualEntrepreneur {
            text = "Votre nom sera suivi de la mention « EI » sur vos documents, comme l'exige le Code de commerce."
        } else if profile.legalForm.isCompany {
            text = "Vos documents mentionneront la forme juridique, le capital social et le RCS."
        }
        if profile.vatRegime == .franchise {
            text += (text.isEmpty ? "" : " ") + "En franchise en base, aucune TVA n'est facturée et la mention « TVA non applicable, art. 293 B du CGI » est ajoutée."
        }
        return text
    }
}

struct IdentitySection: View {
    @Binding var profile: CompanyProfile

    var body: some View {
        Section {
            TextField("Nom commercial", text: $profile.tradeName)
                .textContentType(.organizationName)
            if profile.legalForm.isIndividualEntrepreneur {
                TextField("Prénom et nom de l'entrepreneur", text: $profile.ownerName)
                    .textContentType(.name)
            } else {
                TextField("Raison sociale", text: $profile.legalName)
            }
            if profile.legalForm.isCompany {
                LabeledDecimalRow(label: "Capital social", value: Binding(get: { profile.shareCapital ?? 0 }, set: { profile.shareCapital = $0 == 0 ? nil : $0 }), maxScale: 2)
            }
            TextField("SIREN (9 chiffres)", text: $profile.siren)
                .keyboardType(.numberPad)
            validation(profile.siren, isValid: Identifiers.isValidSIREN, message: "SIREN invalide : vérifiez les 9 chiffres.")
            TextField("SIRET (14 chiffres, facultatif)", text: $profile.siret)
                .keyboardType(.numberPad)
            validation(profile.siret, isValid: Identifiers.isValidSIRET, message: "SIRET invalide : vérifiez les 14 chiffres.")
            if profile.legalForm.isCompany || profile.registry != .none {
                Picker("Registre", selection: $profile.registry) {
                    ForEach(RegistrationRegistry.allCases) { Text($0.label).tag($0) }
                }
                if profile.registry == .rcs || profile.registry == .rm {
                    TextField("Ville d'immatriculation", text: $profile.registryCity)
                }
            }
            if profile.vatRegime == .standard {
                HStack {
                    TextField("N° de TVA intracommunautaire", text: $profile.vatNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if profile.vatNumber.isEmpty, let suggestion = Identifiers.frenchVATNumber(fromSIREN: profile.siren) {
                        Button("Calculer") { profile.vatNumber = suggestion }
                            .font(.footnote.weight(.semibold))
                            .accessibilityHint("Calcule le numéro de TVA à partir du SIREN")
                    }
                }
            }
            TextField("Code APE (facultatif)", text: $profile.apeCode)
                .textInputAutocapitalization(.characters)
        } header: {
            Text("Identité")
        }
    }

    @ViewBuilder
    private func validation(_ value: String, isValid: (String) -> Bool, message: String) -> some View {
        if !value.trimmed.isEmpty && !isValid(value) {
            Text(message).font(.footnote).foregroundStyle(Theme.danger)
        }
    }
}

struct ContactSection: View {
    @Binding var profile: CompanyProfile

    var body: some View {
        Section("Coordonnées") {
            TextField("Adresse", text: $profile.address.line1)
                .textContentType(.streetAddressLine1)
            TextField("Complément d'adresse", text: $profile.address.line2)
                .textContentType(.streetAddressLine2)
            HStack {
                TextField("Code postal", text: $profile.address.postalCode)
                    .textContentType(.postalCode)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 110)
                TextField("Ville", text: $profile.address.city)
                    .textContentType(.addressCity)
            }
            TextField("Email", text: $profile.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField("Téléphone", text: $profile.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            TextField("Site web", text: $profile.website)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
        }
    }
}

struct PaymentTermsSection: View {
    @Binding var profile: CompanyProfile

    var body: some View {
        Section {
            Stepper("Délai de paiement : \(profile.paymentTermsDays) jours", value: $profile.paymentTermsDays, in: 0...60, step: 5)
            Stepper("Validité des devis : \(profile.quoteDefaultValidityDays) jours", value: $profile.quoteDefaultValidityDays, in: 5...180, step: 5)
            TextField("Taux des pénalités de retard", text: $profile.latePenaltyText, axis: .vertical)
            TextField("Escompte (vide = néant)", text: $profile.earlyPaymentDiscountText, axis: .vertical)
        } header: {
            Text("Conditions de paiement")
        } footer: {
            Text("Entre professionnels, le délai ne peut en principe dépasser 60 jours après l'émission. Le taux des pénalités ne peut être inférieur à trois fois le taux d'intérêt légal.")
        }
    }
}

struct BankSection: View {
    @Binding var profile: CompanyProfile

    var body: some View {
        Section {
            TextField("IBAN", text: $profile.iban)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if !profile.iban.trimmed.isEmpty && !Identifiers.isValidIBAN(profile.iban) {
                Text("IBAN invalide (clé de contrôle incorrecte).").font(.footnote).foregroundStyle(Theme.danger)
            }
            TextField("BIC", text: $profile.bic)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Banque", text: $profile.bankName)
        } header: {
            Text("Coordonnées bancaires (facultatif)")
        } footer: {
            Text("Imprimées sur les factures pour faciliter le virement.")
        }
    }
}

struct MentionsSection: View {
    @Binding var profile: CompanyProfile

    var body: some View {
        Section {
            TextField("Assurance professionnelle (assureur, n° de contrat, couverture)", text: $profile.professionalInsurance, axis: .vertical)
            Toggle("Membre d'une association agréée", isOn: $profile.approvedAssociationMember)
            TextField("Mentions complémentaires", text: $profile.additionalMentions, axis: .vertical)
        } header: {
            Text("Mentions légales")
        } footer: {
            Text("L'assurance professionnelle doit figurer sur les devis et factures des activités artisanales concernées (notamment la garantie décennale dans le bâtiment).")
        }
    }
}

/// Lien de paiement en ligne par défaut (Stripe Payment Links, SumUp, PayPal…).
struct OnlinePaymentSection: View {
    @Binding var profile: CompanyProfile

    var body: some View {
        Section {
            TextField("https://buy.stripe.com/…", text: Binding(
                get: { profile.defaultPaymentLink ?? "" },
                set: { profile.defaultPaymentLink = $0.trimmed.isEmpty ? nil : $0.trimmed }))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let link = profile.defaultPaymentLink, !PaymentLink.isValid(link) {
                Text("Le lien doit commencer par https:// et ne pas contenir d'espace.").font(.footnote).foregroundStyle(Theme.danger)
            } else if let link = profile.defaultPaymentLink, let provider = PaymentLink.providerName(link) {
                Label("Lien \(provider) reconnu", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Theme.success)
            }
        } header: {
            Text("Paiement en ligne (facultatif)")
        } footer: {
            Text("Collez un lien de paiement créé dans Stripe (Liens de paiement, avec « le client choisit le montant »), SumUp ou PayPal. Il est imprimé sur vos factures avec un QR code : le client paie par carte. Pensez ensuite à enregistrer le paiement dans DevisMinute.")
        }
    }
}
