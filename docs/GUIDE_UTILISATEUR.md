# Guide utilisateur

## 1. Premier lancement

L'assistant vous demande, en quatre étapes :
1. **Votre statut** : forme juridique et régime de TVA (franchise en base ou assujetti).
2. **Votre entreprise** : nom, SIREN/SIRET (vérifiés automatiquement), capital et RCS pour une société, numéro de TVA (calculé à partir du SIREN si besoin).
3. **Vos coordonnées** : adresse, email, téléphone, et facultativement votre IBAN.
4. **Vos documents** : délai de paiement, modèle et logo.

Tout reste modifiable dans *Plus › Entreprise et documents*.

## 2. Créer un devis

1. *Accueil › + Devis* (ou onglet *Devis* › +).
2. Choisissez un client ou créez-le directement.
3. *Ajouter une prestation* (désignation, quantité, unité, prix HT, TVA, remise) ou *Ajouter depuis le catalogue*.
4. Facultatif : remise globale, acompte demandé, conditions particulières.
5. *Enregistrer* : le devis reçoit son numéro.

Depuis la fiche du devis : *Aperçu et partage du PDF*, *Marquer comme envoyé*, puis *accepté* ou *refusé*. Un devis envoyé dont la date de validité est passée apparaît « Expiré ».

### Faire signer le devis sur l'iPhone

Sur la fiche du devis : *Faire signer le client*. Le client vérifie le montant, coche la mention « Devis reçu avant l'exécution des travaux, bon pour accord » et signe au doigt. Le devis passe en « Accepté », ne peut plus être modifié, et le PDF affiche la signature, le nom, la date et le lieu dans la zone « Bon pour accord ». Une empreinte du devis est enregistrée : la fiche indique si le devis a changé depuis la signature. Il s'agit d'une signature électronique simple (sans certificat).

## 3. Facturer

- **Depuis un devis** : *Convertir en facture*. Les factures d'acompte déjà émises sur ce devis sont déduites automatiquement.
- **Acompte** : *Facturer un acompte* sur un devis envoyé ou accepté.
- **Facture indépendante** : onglet *Factures* › +.

Une facture reste un **brouillon** (sans numéro, sans valeur légale, marquée « Brouillon » sur le PDF) jusqu'à ce que vous touchiez *Émettre la facture*. L'application vérifie alors les mentions obligatoires, attribue le numéro suivant et verrouille le document.

## 4. Corriger une facture émise

Une facture émise ne se modifie plus. Utilisez *Corriger ou annuler par un avoir* :
- **avoir total** : annule la facture ;
- **avoir partiel** : réduit le montant dû (geste commercial, erreur de prix…).

L'avoir est créé en brouillon ; vérifiez-le puis émettez-le. Si nécessaire, établissez ensuite une nouvelle facture correcte.

## 5. Suivre les paiements

Sur une facture émise : *Enregistrer un paiement* (montant, date, moyen). Les paiements partiels sont acceptés ; le solde restant dû est mis à jour. Les factures échues non soldées apparaissent « En retard » sur l'accueil. Les paiements sont déclarés par vous : l'application n'est reliée à aucune banque.

## 5 bis. Paiement en ligne, historique et numérotation existante

- **Paiement en ligne** : créez un lien de paiement dans Stripe (Liens de paiement, option « le client choisit le montant »), SumUp ou PayPal, puis collez-le dans *Plus › Entreprise et documents › Informations de l'entreprise › Paiement en ligne*. Il est ajouté automatiquement aux nouvelles factures, avec un QR code sur le PDF. Il reste modifiable facture par facture. Le paiement n'est pas détecté automatiquement : enregistrez-le dans DevisMinute quand vous le recevez.
- **Factures faites avec un autre logiciel** : *Plus › Sauvegarde, import et export › Importer l'historique de factures (CSV)*. Colonnes : Numéro, Date, Client, Total HT, TVA, Total TTC, Payé, Échéance, Type. Les factures importées servent d'archive (historique client, statistiques, suivi des paiements) ; le document d'origine reste la référence légale.
- **Continuer votre numérotation** : *Plus › Entreprise et documents › Numérotation › Reprendre une numérotation existante*. Indiquez le dernier numéro émis (par exemple F-2026-0057) : la prochaine facture portera le numéro F-2026-0058.

## 6. Clients et catalogue

- *Clients* : recherche, filtre par type, fiche avec historique des devis et factures, facturé, encaissé, reste dû. Un client utilisé dans un document est archivé plutôt que supprimé.
- *Plus › Catalogue* : prestations et produits avec prix HT ou TTC, TVA, unité, coût de revient facultatif. Cochez « Enregistrer dans le catalogue » en créant une ligne pour l'y ajouter.

## 7. Personnaliser vos documents

*Plus › Entreprise et documents › Modèles et apparence* : 8 modèles, couleur principale, typographie, logo, coordonnées bancaires, zone « Bon pour accord ». *Aperçu avec un document d'exemple* montre le rendu réel.

*Numérotation* : formats personnalisables (par exemple `F-{AAAA}-{N:4}` → F-2026-0001).

## 7 bis. Accueil et apparence

- **Objectif du mois** : touchez la carte « Objectif » de l'accueil pour fixer un chiffre d'affaires HT mensuel. L'anneau se remplit avec les factures émises dans le mois, avoirs déduits.
- **À encaisser** : la grande carte de l'accueil montre ce qui reste dû et les montants en retard ; touchez-la pour ouvrir les factures.
- **Icône de l'app** : *Plus › Entreprise et documents › Icône de l'app* (Pétrole, Ivoire ou Nuit).

## 8. Outils

- **Calculateur de rentabilité** : marge brute, taux de marge et de marque, coefficient, prix de vente à partir d'un taux visé.
- **Statistiques** : facturé et encaissé par mois, répartition par client, prestations les plus facturées, devis acceptés et refusés, taux de transformation (à partir de 5 devis concernés).

## 9. Sauvegarder vos données

*Plus › Sauvegarde, import et export* :
- **Créer une sauvegarde** (avec mot de passe recommandé) et l'enregistrer dans Fichiers ou iCloud Drive. Sans le mot de passe, la sauvegarde est irrécupérable.
- **Restaurer** : le fichier est vérifié, un récapitulatif s'affiche, puis vos données sont remplacées.
- **Exports CSV** : factures, TVA, encaissements, devis, clients, catalogue.
- **Imports CSV** : clients et catalogue (colonnes décrites à l'écran).

Conservez vos factures et sauvegardes **10 ans**, hors de l'iPhone.

## 10. Sécurité

*Réglages › Verrouiller avec Face ID* protège l'accès à l'application. Les données sont chiffrées par iOS lorsque l'iPhone est verrouillé. *Plus › Intégrité des factures* vérifie qu'aucune facture émise n'a été altérée.

## 11. Ce que DevisMinute ne fait pas

- Recevoir ou transmettre des factures électroniques via une plateforme agréée (voir *Plus › Conformité et limites*).
- Tenir votre comptabilité ou établir vos déclarations de TVA.
- Encaisser des paiements.
