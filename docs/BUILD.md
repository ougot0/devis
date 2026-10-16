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
| Application iOS (`DevisMinute/`) | Compilée par `xcodebuild` sur GitHub Actions (`macos-15`, simulateur iPhone 16 Pro, SDK iOS 26.2) ; 7 tests d'intégration `AppDataStoreTests` réussis (émission, numérotation, verrouillage, paiements, avoirs, acomptes, sauvegarde/restauration). Workflow : `.github/workflows/ci.yml`. |
| Projet Xcode | Utilisé tel quel par `xcodebuild` en CI ; jamais ouvert dans l'interface d'Xcode |
| Interface utilisateur | **Non testée manuellement** (aucun Mac interactif disponible) : parcours, ergonomie, VoiceOver, Dynamic Type et rendu visuel des écrans restent à vérifier |

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
   Faire de même pour la cible *DevisMinuteWidget* (identifiant `<bundle de l'app>.widget`). L'app et le widget partagent le groupe d'apps `group.com.devisminute.app` : la signature automatique l'enregistre ; si vous changez de préfixe, remplacez-le dans les deux fichiers `Config/*.entitlements`, dans `WidgetBridge.appGroup` et dans `SnapshotProvider.appGroup`.
3. Achats intégrés en test : *Product › Scheme › Edit Scheme › Run › Options › StoreKit Configuration* → `Config/Products.storekit`.
4. Choisir un simulateur iPhone et lancer (⌘R). Tests : ⌘U.

En ligne de commande :

```bash
xcodebuild test -project DevisMinute.xcodeproj -scheme DevisMinute \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

## Reste à faire avant publication

1. Ouvrir le projet dans Xcode, configurer la signature, lancer sur simulateur.
2. Tester sur simulateur puis sur au moins un iPhone réel : premier lancement, création d'un devis en moins de deux minutes, émission, paiement partiel, avoir, aperçu et partage du PDF, sauvegarde chiffrée puis restauration sur un autre appareil, achat intégré en environnement de test (sandbox).
3. Vérifier l'accessibilité : VoiceOver sur les écrans principaux, tailles de texte maximales (Dynamic Type), contraste en mode sombre.
4. Ouvrir les PDF générés dans Aperçu, Adobe Acrobat et sur un PC Windows ; tester l'impression.
5. Faire relire les mentions légales par un expert-comptable (voir `CONFORMITE.md`).
6. Choisir le modèle commercial (`AppConfiguration.monetization`) et le prix.
