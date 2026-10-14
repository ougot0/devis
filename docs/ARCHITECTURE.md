# Architecture

## Principes

1. **Séparation stricte** : la logique métier (`DevisCore`) et la génération PDF (`DevisPDF`) n'importent ni UIKit, ni SwiftUI, ni SwiftData. Elles sont testables sous macOS, iOS et Linux.
2. **Valeurs plutôt qu'objets** : devis, factures, clients et catalogue sont des `struct` `Codable`. L'interface et la persistance manipulent des copies ; les règles sont des fonctions pures.
3. **Exactitude financière** : tous les montants sont des `Decimal`. Aucun `Double` dans un calcul (le `Double` n'apparaît que pour dessiner les graphiques).
4. **Immutabilité des documents émis** : une facture émise est figée (contenu, émetteur, client), scellée, et ne peut plus être modifiée ni supprimée. La seule correction possible passe par un avoir.
5. **Hors ligne et local** : aucune requête réseau, à l'exception de StoreKit (achat intégré) en mode « freemium ».

## Vue d'ensemble

```
┌──────────────────────── Application iOS (DevisMinute/) ───────────────────────┐
│ Features/   Vues SwiftUI : Accueil, Devis, Factures, Clients, Catalogue,       │
│             Statistiques, Rentabilité, Réglages, Sauvegarde, Intégrité…        │
│ Persistence/ DataStore (@Observable, @MainActor) ── orchestre les règles       │
│             Entities (SwiftData) : contenu JSON + colonnes de recherche        │
│ Services/   Export (PDF, XML, fichiers temporaires), StoreKit 2, verrouillage  │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │ appelle
┌───────────────▼──────────── DevisMinuteKit (package Swift) ──────────────────┐
│ DevisCore                                  │ DevisPDF                          │
│  Money (Decimal, arrondis)                 │  PDFWriter (PDF 1.7 natif)        │
│  Domain (entreprise, client, lignes…)      │  Polices standard + métriques AFM │
│  DocumentCalculator (HT, TVA par taux…)    │  TextLayout (césure, coupure)     │
│  Payments (encaissements, retards)         │  DocumentRenderer + 8 modèles     │
│  Numbering (chronologique, continu)        │  (en-têtes, tableau multipage,    │
│  Lifecycle (statuts, conversion, avoirs)   │   totaux, mentions, pieds de page)│
│  Compliance (mentions, contrôles)          │                                   │
│  Integrity (sceaux SHA-256 chaînés)        │                                   │
│  Backup (JSON, SHA-256, AES-256-GCM)       │                                   │
│  CSV, Statistics, Profitability, CII       │                                   │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Persistance (SwiftData)

| Entité | Colonnes indexables | Contenu |
|---|---|---|
| `SettingsEntity` (unique) | — | profil d'entreprise, apparence, logo, états de numérotation, têtes de chaîne des sceaux |
| `CustomerEntity` | nom, type, ville, texte de recherche, archivé | `CustomerRecord` en JSON |
| `CatalogEntity` | nom, catégorie, texte de recherche, archivé | `CatalogItem` en JSON |
| `DocumentEntity` | groupe, type, numéro, date, client, statut, émis, total en centimes | `DocumentRecord` en JSON (document + statut + paiements + sceau) |

Le contenu métier est stocké en JSON (encodeur à clés triées) plutôt qu'en attributs SwiftData : le contenu d'une facture émise est exactement celui qui a été scellé, les `Decimal` ne transitent jamais par un type flottant, et l'évolution du schéma est simplifiée. Les colonnes dupliquées ne servent qu'à l'affichage, au tri et à la recherche.

## Flux principaux

- **Devis** : brouillon → envoyé → accepté / refusé (expiré calculé d'après la date de validité). Numéroté au premier enregistrement. Modifiable tant qu'il n'est ni accepté ni refusé ; sinon, duplication.
- **Facture** : brouillon sans numéro → `DataStore.issue` : figement de l'émetteur, contrôle des mentions (`ComplianceValidator`), numéro chronologique (`NumberingService`), sceau chaîné (`DocumentSealer`), verrouillage.
- **Acompte** : facture d'acompte depuis un devis (TVA ventilée selon les taux du devis), puis déduction automatique dans la facture de solde.
- **Avoir** : total (reprise des lignes) ou partiel ; imputé sur le solde de la facture d'origine.
- **Paiements** : déclarés par l'utilisateur, plafonnés au solde ; état payé / partiel / en retard calculé.

## Génération PDF

Le moteur PDF est écrit en Swift pur (aucune dépendance) : il produit des PDF 1.7 avec les polices standard (Helvetica, Times, Courier — présentes dans tout lecteur PDF) en encodage WinAnsi, qui couvre le français (accents, œ, €, guillemets). Le texte est mesuré avec les métriques AFM officielles, ce qui permet une mise en page exacte et testable : césure, coupure des mots trop longs, répétition de l'en-tête du tableau, découpage d'une ligne trop haute sur deux pages, bloc des totaux insécable, pied de page « page x / n ». Sur iOS, les flux sont compressés via `NSData.compressed(using: .zlib)`.

Limite : les caractères hors WinAnsi (emoji, alphabets non latins) sont remplacés par « ? » et un avertissement est affiché. L'intégration de polices TrueType (et la conformité PDF/A-3 nécessaire à Factur-X) constitue une évolution possible.

## Facturation électronique : point d'intégration

`EInvoicingGateway` (protocole) décrit la transmission d'une facture à une plateforme agréée et la récupération de son statut. L'implémentation actuelle (`NoEInvoicingGateway`) refuse explicitement toute transmission. Une future connexion à une plateforme agréée (API REST du prestataire choisi) s'implémentera derrière ce protocole, sans modifier le reste de l'application. `CIIExporter` produit déjà les données structurées au format CII, à valider.

## Sécurité et confidentialité

- Droit `com.apple.developer.default-data-protection = NSFileProtectionComplete` : la base est chiffrée par iOS et inaccessible tant que l'appareil est verrouillé (l'application n'effectue aucun travail en arrière-plan).
- Verrouillage facultatif par Face ID / Touch ID / code.
- Sauvegardes chiffrables (AES-256-GCM, clé dérivée par PBKDF2-HMAC-SHA256, 600 000 itérations).
- Fichiers temporaires de partage écrits avec `.completeFileProtection` et purgés au lancement.
- Manifeste de confidentialité : aucune collecte, aucun pistage.
