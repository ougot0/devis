# Compilation et tests

## Prérequis

- **Xcode 16 ou plus récent** (le projet utilise les dossiers synchronisés, format d'objet 77). Avec une version plus ancienne, régénérez le projet avec XcodeGen : `brew install xcodegen && xcodegen generate`.
- Cible minimale : **iOS 17** (SwiftData, `@Observable`, Swift Charts).
- Un compte Apple Developer (99 €/an) pour installer sur un iPhone et publier.

## Ce qui a été vérifié, et comment

| Élément | Vérification réalisée |
|---|---|
| `DevisCore` (calculs, numérotation, statuts, conformité, sceaux, sauvegarde, CSV, statistiques, rentabilité, CII) | Compilé et testé sous Linux (Swift 6.0.3) : 81 tests |
| `DevisPDF` (moteur PDF, 8 modèles, multipage) | Compilé et testé sous Linux : 13 tests ; PDF validés structurellement (table xref) et contrôlés visuellement après conversion en images (poppler) |
| Application iOS (`DevisMinute/`) | **Non compilée à ce stade** : SwiftUI, SwiftData et StoreKit n'existent pas sous Linux. Le workflow `.github/workflows/ci.yml` la compile et lance ses tests sur macOS (GitHub Actions). |
| Projet Xcode | Analysé par un lecteur `pbxproj` indépendant ; **non ouvert dans Xcode** |

## Moteur métier

```bash
swift test --package-path DevisMinuteKit
```

Pour inspecter les PDF produits par les tests :

```bash
DEVIS_PDF_OUTPUT=/tmp/devis-pdf swift test --package-path DevisMinuteKit --filter DevisPDFTests
open /tmp/devis-pdf
```

Sous Linux, le package utilise `swift-crypto` (Apple, licence Apache 2.0) à la place de CryptoKit. Xcode résout cette dépendance au premier chargement (connexion requise une fois), mais ne la lie pas à l'application iOS.

## Application

1. Ouvrir `DevisMinute.xcodeproj`.
2. Cible *DevisMinute* › *Signing & Capabilities* : choisir votre équipe (Team) et, si nécessaire, un identifiant de bundle à vous (`com.votresociete.devisminute`). Reporter le même préfixe dans `AppConfiguration.premiumProductID` et dans `Config/Products.storekit`.
3. Achats intégrés en test : *Product › Scheme › Edit Scheme › Run › Options › StoreKit Configuration* → `Config/Products.storekit`.
4. Choisir un simulateur iPhone et lancer (⌘R). Tests : ⌘U.

En ligne de commande :

```bash
xcodebuild test -project DevisMinute.xcodeproj -scheme DevisMinute \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

## Reste à faire avant publication

1. Faire passer la compilation iOS dans Xcode et corriger les éventuelles erreurs (code écrit sans compilateur iOS).
2. Tester sur simulateur puis sur au moins un iPhone réel : premier lancement, création d'un devis en moins de deux minutes, émission, paiement partiel, avoir, aperçu et partage du PDF, sauvegarde chiffrée puis restauration sur un autre appareil, achat intégré en environnement de test (sandbox).
3. Vérifier l'accessibilité : VoiceOver sur les écrans principaux, tailles de texte maximales (Dynamic Type), contraste en mode sombre.
4. Ouvrir les PDF générés dans Aperçu, Adobe Acrobat et sur un PC Windows ; tester l'impression.
5. Faire relire les mentions légales par un expert-comptable (voir `CONFORMITE.md`).
6. Choisir le modèle commercial (`AppConfiguration.monetization`) et le prix.
