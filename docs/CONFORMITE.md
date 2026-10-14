# Conformité française : règles appliquées et limites à faire vérifier

> Ce document décrit ce que l'application met en œuvre et ce qu'elle **ne garantit pas**. Il ne constitue pas un avis juridique. **DevisMinute n'est ni certifié ni déclaré conforme** par un organisme ; avant publication, faites relire les mentions et les flux par un expert-comptable ou un avocat.
>
> Sources consultées le 14/10/2026 :
> - [Mentions obligatoires sur une facture — service-public.fr (F31808), vérifiée le 11/08/2026](https://entreprendre.service-public.gouv.fr/vosdroits/F31808)
> - [Obligation de facturation électronique — service-public.fr (F39785), vérifiée le 07/08/2026](https://entreprendre.service-public.gouv.fr/vosdroits/F39785)
> - [Certification des logiciels de caisse — economie.gouv.fr](https://www.economie.gouv.fr/entreprises/gerer-son-entreprise-au-quotidien/gerer-sa-comptabilite-et-ses-demarches/ce-quil-faut-savoir-sur-la-certification-des-logiciels-de-caisse) et [BOFiP ACTU-2026-00073](https://bofip.impots.gouv.fr/bofip/15035-PGP.html/ACTU-2026-00073)
> - Code de commerce L441-9, L441-10, D441-5, R526-27 ; CGI art. 242 nonies A ann. II, 289, 293 B.

## 1. Mentions imprimées

| Mention | Mise en œuvre | Code |
|---|---|---|
| Date d'émission, numéro unique chronologique et continu | Numéro attribué à l'émission, contrôle de chronologie | `NumberingService` |
| Date de la vente / de la prestation | Champ « date de la prestation » | éditeur |
| Identité du vendeur : nom + « EI » (entrepreneur individuel), dénomination, forme, capital, siège, SIREN/SIRET, RCS/RM | Pied de page légal sur chaque page | `LegalMentionsBuilder.sellerLegalLine` |
| N° de TVA du vendeur et du client professionnel (sauf ≤ 150 € HT) | Contrôle bloquant (vendeur) / avertissement (client) | `ComplianceValidator` |
| Identité et adresse du client | Contrôle bloquant (professionnel), avertissement (particulier) | idem |
| N° de bon de commande | Champ « référence de commande » | éditeur |
| Désignation, quantité, prix unitaire HT, taux de TVA, remises | Tableau des prestations | `DevisPDF` |
| Totaux HT, TVA par taux, TTC | Bloc des totaux | `DocumentCalculator` |
| Date d'échéance, escompte (« néant » par défaut) | Mentions de bas de page | `LegalMentionsBuilder` |
| Taux des pénalités de retard | Texte paramétrable (« trois fois le taux d'intérêt légal » par défaut) | idem |
| Indemnité forfaitaire de 40 € | Uniquement pour un client professionnel | idem |
| Franchise en base : « TVA non applicable, art. 293 B du CGI » | Automatique, TVA forcée à 0 | idem |
| Autoliquidation | Option par document, TVA à 0, mention « Autoliquidation » | idem |
| Option pour la TVA sur les débits | Option du profil, imprimée si prestations de services | idem |
| Assurance professionnelle (activités artisanales) | Champ du profil | idem |
| Membre d'une association agréée | Option du profil | idem |
| **Réforme 2026-2027** : SIREN du client, adresse de livraison si différente, nature des opérations (biens / services / mixte), option sur les débits | SIREN client imprimé et contrôlé (information avant le 01/09/2027, bloquant ensuite) ; adresse de livraison ; nature calculée d'après les lignes | `ComplianceValidator`, `operationNatureLabel` |

**À faire vérifier** :
- la mention de la **garantie légale de conformité** (ventes de certains biens à des particuliers) n'est pas ajoutée automatiquement : à saisir dans les mentions complémentaires si l'activité est concernée ;
- les mentions propres à certaines professions (professions réglementées, agents commerciaux, éco-participation DEEE, copie privée, auto-facturation) ne sont pas gérées spécifiquement ;
- la règle de délai de paiement (60 jours ou 45 jours fin de mois entre professionnels, exceptions sectorielles) n'est contrôlée que sur le plafond de 60 jours, par un simple avertissement ;
- le taux de pénalités saisi n'est pas contrôlé par rapport au minimum légal.

## 2. Devis

Le devis comporte les informations du vendeur et du client, la date, la durée de validité, le détail chiffré, les conditions particulières, l'acompte demandé et une zone « Bon pour accord ». **À vérifier** : les devis obligatoires de certains secteurs (dépannage, travaux, services à la personne…) imposent des mentions spécifiques (frais de déplacement, caractère gratuit ou payant du devis, etc.) qui ne sont pas générées automatiquement.

## 3. Numérotation, inaltérabilité et conservation

- Factures et factures d'acompte partagent une séquence continue ; les avoirs ont leur propre séquence. Le numéro n'est attribué qu'à l'émission : un brouillon supprimé ne crée jamais de trou.
- Une date d'émission antérieure à celle de la dernière facture émise est refusée.
- Une facture émise ne peut être ni modifiée ni supprimée (contrôles dans `AppDataStore.save` et `AppDataStore.delete`). Les corrections passent par un avoir qui référence la facture d'origine.
- Chaque document émis reçoit une empreinte SHA-256 chaînée à la précédente (`DocumentSealer`). Un écran permet de vérifier la chaîne.

**Limites** :
- ces protections sont **locales** : un utilisateur qui restaure une ancienne sauvegarde ou réinstalle l'application peut revenir en arrière. Ce n'est ni un archivage à valeur probante, ni une signature électronique, ni une certification ;
- la conservation légale (10 ans pour les pièces comptables, Code de commerce L123-22 ; 6 ans au titre du droit fiscal) repose sur les sauvegardes exportées par l'utilisateur. L'application le rappelle mais ne peut pas le garantir ;
- les factures émises sur papier ou PDF doivent, selon l'administration, être conservées dans leur forme d'origine : conserver les PDF envoyés (et pas seulement les données).

## 4. Facturation électronique (réforme)

Calendrier officiel (service-public.fr, F39785) :

| | Réception | Émission | E-reporting |
|---|---|---|---|
| Grandes entreprises, ETI | 1er septembre 2026 | 1er septembre 2026 | 1er septembre 2026 |
| PME, micro-entreprises | **1er septembre 2026** | **1er septembre 2027** | 1er septembre 2027 |

Les factures électroniques doivent être émises, reçues et transmises **via une plateforme agréée (PA)** ; l'annuaire national indique la plateforme de réception de chaque entreprise.

**Conséquences pour DevisMinute** :
- l'application **ne reçoit pas** de factures électroniques : depuis le 1er septembre 2026, chaque utilisateur assujetti doit disposer d'une plateforme agréée pour la réception, indépendamment de DevisMinute ;
- un PDF produit par DevisMinute **n'est pas une facture électronique** au sens de la réforme. Jusqu'au 31 août 2027, une PME ou micro-entreprise peut continuer à émettre ses factures B2B dans ce format (sous réserve de confirmation par l'utilisateur de sa situation) ; à partir du 1er septembre 2027, ses factures B2B domestiques devront passer par une plateforme agréée ;
- l'export XML CII est une **aide préparatoire non validée** (pas de contrôle Schematron, pas de PDF/A-3 Factur-X, pas de transmission) ;
- l'**e-reporting** (ventes aux particuliers, opérations internationales, données de paiement) n'est pas pris en charge ;
- le protocole `EInvoicingGateway` prévoit l'intégration future d'une plateforme agréée. Ces plateformes sont des services tiers, en général **payants** : leur intégration sortirait du cadre « sans coût récurrent ».

**Recommandation pour la fiche App Store** : présenter DevisMinute comme un outil de création de devis et de factures PDF et de suivi, et indiquer clairement qu'il ne remplace pas une plateforme agréée de facturation électronique.

## 5. Logiciel de caisse (art. 286, I-3° bis du CGI)

Les assujettis à la TVA qui enregistrent les règlements de clients **particuliers** dans un logiciel doivent utiliser un logiciel certifié ou couvert par une attestation individuelle de l'éditeur (attestation rétablie par la loi de finances pour 2026, art. 125). Les entreprises en franchise en base ne sont pas concernées.

DevisMinute permet de **déclarer** des encaissements sur des factures : il ne s'agit pas d'un système de caisse, mais l'administration pourrait apprécier cette fonction différemment pour des ventes à des particuliers. **À faire analyser par un professionnel avant publication**. Options : (a) limiter le suivi des paiements aux clients professionnels pour les utilisateurs assujettis ; (b) fournir une attestation d'éditeur conforme au modèle officiel (BOI-LETTRE-000242) après mise en conformité aux conditions d'inaltérabilité, de sécurisation, de conservation et d'archivage ; (c) indiquer clairement que l'application n'est pas un logiciel d'encaissement.

## 6. Statuts juridiques

| Statut | Particularités appliquées |
|---|---|
| Micro-entrepreneur | EI ; franchise en base par défaut (modifiable) ; mention 293 B |
| Entrepreneur individuel | Nom suivi de « EI » |
| EURL, SARL, SAS, SASU, SA, SNC, SELARL | Forme, capital social, siège, RCS ; avertissements si absents |

**À vérifier** : seuils de franchise (37 500 € pour les services, 85 000 € pour les ventes en 2026, selon les sources consultées, non officielles sur ce point). L'application ne surveille pas le chiffre d'affaires par rapport à ces seuils.

## 7. Données personnelles (RGPD)

Les données des clients sont stockées uniquement sur l'appareil de l'utilisateur, qui est responsable de leur traitement. L'éditeur ne collecte rien. Une politique de confidentialité doit néanmoins être publiée (URL exigée par l'App Store), voir `PUBLICATION.md`.
