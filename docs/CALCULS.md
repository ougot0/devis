# Règles de calcul et d'arrondi

Implémentation : `DevisMinuteKit/Sources/DevisCore/Money/Money.swift` et `Calculation/DocumentCalculator.swift`. Tests : `Tests/DevisCoreTests/MoneyTests.swift`, `CalculatorTests.swift`.

## Type numérique

Tous les montants, quantités et taux sont des `Decimal` (base 10, 38 chiffres significatifs). `0,1 + 0,2 = 0,3` exactement ; 1 000 additions de 0,01 donnent exactement 10.

## Règles

| Règle | Description |
|---|---|
| **R1** | Prix unitaires et quantités : 4 décimales au maximum. Un prix catalogue saisi TTC est converti en HT à 4 décimales. |
| **R2** | Montant HT d'une ligne = arrondi au centime de (quantité × prix unitaire), moins la remise de ligne (elle-même arrondie au centime et plafonnée au montant de la ligne). |
| **R3** | Remise globale (en % ou en €) calculée sur le sous-total HT, arrondie au centime, puis répartie entre les taux de TVA au prorata des bases, par la méthode du plus fort reste : la somme des bases est toujours exactement le total HT. |
| **R4** | TVA calculée **par taux** sur la base HT totale de ce taux, arrondie au centime (et non ligne par ligne). |
| **R5** | Total TTC = total HT + total TVA. |
| **R6** | Facture d'acompte : une ligne par taux de TVA du devis, au prorata. La TVA étant calculée sur la base HT (R4), certains montants TTC ne sont pas atteignables au centime près ; l'écart, reporté d'un taux à l'autre, est au plus d'un centime. |

Arrondi : « arrondi commercial », au demi supérieur en valeur absolue (0,005 → 0,01 ; −0,005 → −0,01).

Franchise en base et autoliquidation : la TVA est forcée à 0 quel que soit le taux saisi sur les lignes.

## Exemples vérifiés par les tests

| Cas | Résultat |
|---|---|
| 3 lignes à 0,33 € HT, TVA 20 % | HT 0,99 ; TVA 0,20 (par taux) — et non 0,21 (par ligne) |
| 1,333 h × 37,50 € | 49,99 € HT |
| Lignes à 10 %, 20 % et 5,5 % | TVA 40,00 + 40,00 + 12,65 ; TTC 922,64 € |
| Remise de ligne 5 % puis remise globale 10 % sur deux taux | somme des bases = total HT |
| Facture de 1 200 € TTC, acompte de 360 € déduit | net à payer 840 € |
| Paiements de 3 × 0,01 € sur une facture de 0,03 € | solde 0 |

## Indicateurs

- **Facturé** : factures et factures d'acompte émises, avoirs déduits. Pour une facture de solde, les acomptes déjà facturés sont exclus (pas de double comptage) ; en HT, l'exclusion est faite au prorata du net à payer.
- **Encaissé** : paiements déclarés, à leur date.
- **Restant dû** : montant dû − avoirs imputés − paiements, jamais négatif.
- **Taux de transformation des devis** : acceptés ÷ (acceptés + refusés + expirés), affiché seulement à partir de 5 devis concernés.

## Rentabilité

| Indicateur | Formule |
|---|---|
| Prix de vente net | prix de vente × (1 − remise) |
| Marge brute | prix de vente net − coût de revient |
| Taux de marge | marge brute ÷ coût de revient |
| Taux de marque | marge brute ÷ prix de vente net |
| Coefficient multiplicateur | prix de vente net ÷ coût de revient |
| Bénéfice brut estimé | marge brute × quantité |
