import SwiftUI
import DevisCore

/// Vérification de l'intégrité des factures émises (sceaux chaînés, continuité).
struct IntegrityView: View {
    @Environment(DataStore.self) private var store
    @State private var problems: [String]?
    @State private var issuedCount = 0

    var body: some View {
        List {
            Section {
                Button("Lancer la vérification") { verify() }
                if let problems {
                    if problems.isEmpty {
                        Label("\(issuedCount) document(s) émis vérifié(s) : aucune anomalie.", systemImage: "checkmark.seal")
                            .foregroundStyle(Theme.success)
                    } else {
                        ForEach(problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.danger)
                        }
                    }
                }
            } footer: {
                Text("Chaque facture et chaque avoir reçoivent à l'émission une empreinte SHA-256 de leur contenu, chaînée à celle du document précédent. Toute modification ou suppression ultérieure est ainsi détectable. Il s'agit d'une protection locale : elle ne vaut pas certification.")
            }
        }
        .navigationTitle("Intégrité")
        .appBackground()
    }

    private func verify() {
        issuedCount = store.allRecords().filter(\.isIssuedInvoice).count
        problems = store.integrityReport()
    }
}

/// Informations de conformité et limites de l'application, affichées dans l'application.
struct ComplianceInfoView: View {
    var body: some View {
        List {
            Section("Facturation électronique (réforme 2026-2027)") {
                Text("Depuis le 1er septembre 2026, toutes les entreprises assujetties à la TVA en France doivent pouvoir **recevoir** des factures électroniques. L'**émission** devient obligatoire le 1er septembre 2027 pour les PME et micro-entreprises (dès 2026 pour les grandes entreprises et ETI).")
                Text("Ces échanges passent obligatoirement par une **plateforme agréée** choisie par l'entreprise. DevisMinute fonctionne hors ligne et **n'est relié à aucune plateforme agréée** : un PDF créé par l'application n'est pas une facture électronique au sens de la réforme.")
                Text("L'export « données structurées (XML CII) » est une aide préparatoire, non validée par une plateforme.")
            }
            Section("Ce que fait DevisMinute") {
                Text("• Mentions obligatoires selon votre statut (EI, société, franchise en base, autoliquidation, débits).\n• Numérotation chronologique et continue, attribuée à l'émission.\n• Factures émises non modifiables ; corrections par avoir.\n• Contrôle des informations manquantes avant émission.\n• Empreintes d'intégrité locales et sauvegardes vérifiées.")
            }
            Section("Ce qui reste de votre responsabilité") {
                Text("• Vérifier l'adéquation des mentions à votre activité (avec votre expert-comptable si besoin).\n• Conserver vos factures 10 ans (Code de commerce) et vos sauvegardes hors de l'iPhone.\n• Choisir une plateforme agréée pour recevoir vos factures fournisseurs, et pour émettre vos factures à partir des échéances applicables.\n• Les paiements sont déclarés par vous : DevisMinute n'est pas un logiciel de caisse certifié.")
            }
            Section("Sources officielles") {
                Link("Mentions obligatoires sur une facture (service-public.fr)", destination: URL(string: "https://entreprendre.service-public.gouv.fr/vosdroits/F31808")!)
                Link("Obligation de facturation électronique (service-public.fr)", destination: URL(string: "https://entreprendre.service-public.gouv.fr/vosdroits/F39785")!)
                Link("Facturation électronique (impots.gouv.fr)", destination: URL(string: "https://www.impots.gouv.fr/professionnel/je-passe-la-facturation-electronique")!)
            }
            Section {
                Text("Informations vérifiées le 14 octobre 2026. La réglementation évolue : consultez les sources officielles.")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
        }
        .navigationTitle("Conformité")
        .appBackground()
    }
}
