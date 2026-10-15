# DevisMinute : project summary

*Written on 15/10/2026 to share the project's progress with everyone involved.*

## 1. The idea

An iPhone app that lets French independents (tradespeople, micro-entrepreneurs, freelancers, small businesses) create **quotes and invoices** quickly, track **payments** and keep a **client directory**. Commercial goal: App Store, either a paid app at about €9.99 or free with a one-time unlock. No subscription, no ads.

Constraints from the initial brief:
- native app (Swift / SwiftUI), works **fully offline**, data stays on the iPhone;
- **no server, no paid API, no AI**, no recurring cost;
- clean professional design (ivory background, petrol blue, charcoal, no gimmicks);
- **first quote in under 2 minutes** once the company is set up;
- serious about **French rules** (mandatory mentions, numbering, VAT, credit notes, e-invoicing reform).

## 2. What exists today

| Part | Status |
|---|---|
| Calculation engine (exact amounts, VAT per rate, discounts, deposits, payments) | ✅ done and tested |
| Invoice numbering (chronological, no gaps), issued invoices locked, credit notes | ✅ done and tested |
| Mandatory-mention checks before issuing an invoice | ✅ done and tested |
| PDF generator, **8 templates** (Classic, Corporate, Minimal, Craftsman, Creative, Elegant, Technical, Modern) | ✅ done and tested |
| iPhone app: home, quotes, invoices, clients, catalog, statistics, profitability, settings, backup | ✅ written, compiles, launches on the simulator |
| Encrypted backup + checked restore, CSV exports/imports | ✅ done and tested |
| Documentation (building, App Store publishing, user guide, compliance) | ✅ in the `docs/` folder |
| **Hands-on testing on a real iPhone** | ❌ not done yet |

In total, 101 automated tests pass, and they run on every change (GitHub Actions).

## 3. Screenshots

The app on an iPhone simulator, with fictional data.

| | | |
|---|---|---|
| ![Wizard](docs/captures/01-assistant.png) | ![Home](docs/captures/02-accueil.png) | ![Quotes](docs/captures/03-devis.png) |
| Setup wizard | Home | Quote list |
| ![Editor](docs/captures/04-editeur-devis.png) | ![PDF](docs/captures/05-apercu-pdf.png) | ![Invoices](docs/captures/06-factures.png) |
| Quote editor | PDF preview | Invoices |
| ![Invoice page](docs/captures/07-fiche-facture.png) | ![Statistics](docs/captures/09-statistiques.png) | ![Dark mode](docs/captures/11-accueil-sombre.png) |
| Invoice page | Statistics | Dark mode |

The 8 PDF templates:

![The 8 templates](docs/modeles.png)

## 4. Important points to know

- **E-invoicing**: since 1 September 2026, every business must be able to *receive* e-invoices through an approved platform. From 1 September 2027, small businesses and micro-entrepreneurs will also have to *send* them that way. The app creates PDFs and **does not connect to an approved platform**. It needs to be marketed honestly as a quote/invoice tool, not as an "e-invoicing" solution. Details: [docs/CONFORMITE.md](docs/CONFORMITE.md).
- **Payment tracking**: for businesses that charge VAT and sell to private individuals, there's a question around the "certified till software" rule. This needs to be checked with an accountant.
- **Visible code**: the GitHub repository is currently **public**. Before commercialising, it may be worth making it private.

## 5. What remains to be done

1. Test the app hands-on on a Mac (Xcode) and then on a real iPhone.
2. Fix two small defects spotted on the screenshots:
   - the setup wizard cuts off long labels;
   - a mistake in the demo data (only affects the fake data).
3. Create an Apple Developer account (€99/year), a final icon, a privacy page.
4. Have the legal mentions reviewed by an accountant.
5. Choose the business model and the price.

## 6. Questions to settle together

- Paid at €9.99, or free plus a one-time purchase? If free, what should the free version include?
- Which user to target first (tradespeople/construction, freelancers, everyone)?
- Is it worth connecting an approved e-invoicing platform later? That service would be paid.
- Who has a Mac to test and publish?

## 7. Where to find what

- Full code: this repository (`DevisMinute/` for the app, `DevisMinuteKit/` for the engine).
- [User guide](docs/GUIDE_UTILISATEUR.md): how the app works, screen by screen.
- [App Store publishing](docs/PUBLICATION.md) and the [proposed App Store listing](docs/FICHE_APP_STORE.md).
- [Build](docs/BUILD.md): how to compile and test.
