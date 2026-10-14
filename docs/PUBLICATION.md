# Publication sur l'App Store

## 1. Décisions préalables

| Décision | Où la reporter |
|---|---|
| Modèle commercial : payante (≈ 9,99 €) **ou** gratuite + achat unique | `AppConfiguration.monetization` (`DevisMinute/Services/PurchaseManager.swift`) |
| Identifiant de bundle définitif | Réglages de la cible (`PRODUCT_BUNDLE_IDENTIFIER`), `project.yml` |
| Identifiant du produit intégré | `AppConfiguration.premiumProductID`, `Config/Products.storekit`, App Store Connect |
| Statut juridique de l'éditeur, mentions légales, politique de confidentialité | Site web de l'éditeur |

En mode `.paidUpfront`, aucun achat intégré n'est présenté (toutes les fonctions sont incluses). En mode `.freemium`, la version gratuite n'est jamais limitée sur l'essentiel (création, émission, sauvegarde) ; l'achat unique débloque les 6 modèles supplémentaires, les statistiques, les exports CSV et l'export XML.

## 2. Compte et App Store Connect

1. Adhérer à l'Apple Developer Program (99 €/an).
2. Accepter l'accord **Paid Applications** et renseigner les informations bancaires et fiscales (indispensable pour une application payante ou des achats intégrés).
3. Statut de **commerçant (trader)** au titre du DSA européen : obligatoire pour distribuer dans l'UE ; adresse, téléphone et email affichés sur la fiche.
4. Créer l'application dans App Store Connect (nom, langue principale : français, identifiant de bundle, SKU).
5. Mode freemium : créer l'achat intégré non consommable avec le même identifiant, son prix, sa localisation, une capture et une note pour l'examen.

## 3. Conformité et déclarations

- **Confidentialité** (« App Privacy ») : « Données non collectées ». Le manifeste `PrivacyInfo.xcprivacy` est fourni.
- **Politique de confidentialité** : URL obligatoire. Elle doit indiquer que les données restent sur l'appareil, qu'aucune donnée n'est transmise à l'éditeur, et rappeler que l'utilisateur est responsable du traitement des données de ses clients.
- **Chiffrement (export compliance)** : l'application utilise du chiffrement (AES-GCM de CryptoKit pour les sauvegardes, HTTPS de StoreKit). Répondre au questionnaire d'App Store Connect ; ce type d'usage relève en général des exemptions, mais **à confirmer**. La **France** impose des formalités pour les moyens de cryptologie : vérifier auprès de l'ANSSI si une déclaration est requise (Apple le rappelle pour une distribution en France). Une fois la réponse établie, ajouter la clé `ITSAppUsesNonExemptEncryption` au projet.
- **Classification par âge** : 4+.
- **Catégorie** : Économie et entreprise (secondaire : Productivité).
- Vérifier que la fiche ne promet aucune conformité « facture électronique » (voir `CONFORMITE.md`).

## 4. Préparer la version

1. Incrémenter `MARKETING_VERSION` (1.0) et `CURRENT_PROJECT_VERSION` (numéro de build).
2. Remplacer l'icône provisoire (`DevisMinute/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 × 1024, sans transparence) par une icône définitive.
3. Tests complets sur iPhone réel (voir `BUILD.md`, « Reste à faire »).
4. *Product › Archive*, puis *Distribute App › App Store Connect › Upload*.
5. TestFlight : tests internes, puis externes (examen bêta) avec quelques professionnels.

## 5. Soumission

- Captures d'écran : iPhone 6,9" (1320 × 2868) obligatoire ; voir `FICHE_APP_STORE.md` pour les écrans conseillés.
- Notes pour l'examen : « L'application fonctionne entièrement hors ligne, sans compte. Au premier lancement, un assistant demande des informations d'entreprise : des valeurs fictives conviennent (SIREN de test : 732829320). L'achat intégré débloque les modèles supplémentaires et les statistiques. »
- Pour l'achat intégré, StoreKit est testable en sandbox ; vérifier la restauration des achats.
- Points d'attention fréquents de l'examen : bouton « Restaurer les achats » présent (écran *Version complète*), aucune fonction factice, pas de lien vers un paiement externe.

## 6. Après publication

- Suivre les rapports de plantage (Xcode Organizer) et les avis.
- Réévaluer à chaque évolution réglementaire : `ComplianceValidator.smeEInvoicingIssuanceDate`, textes de `LegalTexts`, écran *Conformité et limites* (date de vérification).
