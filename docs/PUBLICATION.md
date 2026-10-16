# Publication sur l'App Store

## 1. Décisions préalables

| Décision | Où la reporter |
|---|---|
| Modèle commercial retenu : **gratuite + achat unique de 4,99 €** (non consommable, sans abonnement) | `AppConfiguration.monetization` (`DevisMinute/Services/PurchaseManager.swift`) |
| Identifiant de bundle définitif | Réglages de la cible (`PRODUCT_BUNDLE_IDENTIFIER`), `project.yml` |
| Identifiant du produit intégré | `AppConfiguration.premiumProductID`, `Config/Products.storekit`, App Store Connect |
| Statut juridique de l'éditeur, mentions légales, politique de confidentialité | Site web de l'éditeur |

En mode `.paidUpfront`, aucun achat intégré n'est présenté (toutes les fonctions sont incluses). En mode `.freemium`, la version gratuite n'est jamais limitée sur l'essentiel (création, émission, sauvegarde) ; l'achat unique débloque les 6 modèles supplémentaires, les statistiques, les exports CSV et l'export XML.

## 2. Compte et App Store Connect

1. Adhérer à l'Apple Developer Program (99 €/an).
2. Accepter l'accord **Paid Applications** et renseigner les informations bancaires et fiscales (indispensable pour une application payante ou des achats intégrés).
3. Statut de **commerçant (trader)** au titre du DSA européen : obligatoire pour distribuer dans l'UE ; adresse, téléphone et email affichés sur la fiche.
4. Créer l'application dans App Store Connect (nom, langue principale : français, identifiant de bundle, SKU). Les identifiants `com.devisminute.app`, `com.devisminute.app.widget` et le groupe d'apps `group.com.devisminute.app` sont créés automatiquement par la signature automatique d'Xcode (ou à créer dans *Certificates, Identifiers & Profiles*).
5. Créer l'achat intégré **non consommable** `com.devisminute.app.premium` au prix de **4,99 €** (palier tarifaire correspondant), avec sa localisation, une capture et une note pour l'examen.
6. Activer la capacité **Se connecter avec Apple** sur l'identifiant de l'app (la signature automatique d'Xcode le fait). Le compte est facultatif et se supprime dans l'app (*Plus › Mon compte › Supprimer mon compte*), comme l'exige la règle 5.1.1(v) de l'App Store. Aucun serveur n'est utilisé.

## 3. Conformité et déclarations

- **Confidentialité** (« App Privacy ») : déclarer **Coordonnées › Adresse e-mail**, liée à l'utilisateur, utilisée pour le **fonctionnement de l'app**, sans pistage (compte e-mail facultatif). Le manifeste `PrivacyInfo.xcprivacy` le déclare déjà.
- **Compte e-mail (Supabase)** : projet « DevisMinute » (région Paris), fonction `delete-account` déployée. Avant la publication, dans le tableau de bord Supabase :
  1. *Authentication › URL Configuration › Site URL* : une page publique (par exemple la page de la politique de confidentialité) vers laquelle renvoient les liens de confirmation ;
  2. *Authentication › Emails › SMTP Settings* : brancher un service d'envoi (Resend, Brevo… offre gratuite) — l'envoi intégré de Supabase ne livre qu'aux membres de l'équipe et est limité à quelques e-mails par heure ;
  3. *Authentication › Emails › Templates* : traduire les e-mails de confirmation et de réinitialisation en français.
- **Politique de confidentialité** : URL obligatoire. Texte prêt dans `docs/CONFIDENTIALITE.md` : les documents restent sur l'appareil, seul l'e-mail du compte facultatif est enregistré en ligne (Supabase, Paris), et l'utilisateur reste responsable des données de ses clients.
- **Chiffrement (export compliance)** : l'application utilise du chiffrement (AES-GCM de CryptoKit pour les sauvegardes, HTTPS de StoreKit). Répondre au questionnaire d'App Store Connect ; ce type d'usage relève en général des exemptions, mais **à confirmer**. La **France** impose des formalités pour les moyens de cryptologie : vérifier auprès de l'ANSSI si une déclaration est requise (Apple le rappelle pour une distribution en France). Une fois la réponse établie, ajouter la clé `ITSAppUsesNonExemptEncryption` au projet.
- **Autorisations demandées** : appareil photo (scan des justificatifs de dépenses), notifications (rappels d'échéance), Face ID (verrouillage). Aucune n'est obligatoire pour utiliser l'application.
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
