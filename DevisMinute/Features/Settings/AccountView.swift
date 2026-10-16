import SwiftUI
import AuthenticationServices

/// « Mon compte » : connexion avec Apple (facultative), version complète, déconnexion et suppression.
struct AccountView: View {
    @Environment(AccountManager.self) private var accounts
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let account = accounts.account {
                Section {
                    HStack(spacing: Theme.Space.m) {
                        InitialsAvatar(name: account.name.isEmpty ? "Moi" : account.name, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name.isEmpty ? "Compte Apple" : account.name).font(.title3.weight(.semibold))
                            if !account.email.isEmpty {
                                Text(account.email).font(.footnote).foregroundStyle(Theme.neutral)
                            }
                            Text("Membre depuis le \(account.createdAt.formatted(date: .long, time: .omitted))")
                                .font(.caption).foregroundStyle(Theme.neutral)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Créez votre compte").font(.title3.weight(.semibold))
                        Text("En une touche avec votre identifiant Apple : pas de mot de passe à retenir. Vous pouvez masquer votre e-mail. Le compte est facultatif : l'application fonctionne entièrement sans.")
                            .font(.footnote).foregroundStyle(Theme.neutral)
                    }
                    .padding(.vertical, Theme.Space.xs)
                    SignInWithAppleButton(.signUp, onRequest: { accounts.configure($0) }, onCompletion: { accounts.handle($0) })
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 48)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    if let error = accounts.lastError { Text(error).foregroundStyle(Theme.danger) }
                }
            }

            Section("Version complète") {
                LabeledContent("Statut") {
                    Text(purchases.isPremium ? "Active" : "Gratuite")
                        .foregroundStyle(purchases.isPremium ? Theme.success : Theme.neutral)
                }
                if !purchases.isPremium {
                    NavigationLink("Débloquer pour \(purchases.product?.displayPrice ?? "4,99 €"), une seule fois") { PremiumView() }
                }
                Button("Restaurer mes achats") { Task { await purchases.restore() } }
            }

            if accounts.isSignedIn {
                Section {
                    Button("Se déconnecter") { accounts.signOut() }
                    Button("Supprimer mon compte", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Vos devis, factures et clients restent sur cet iPhone. Pour retirer complètement l'accès, allez aussi dans Réglages › [votre nom] › Connexion et sécurité › Se connecter avec Apple.")
                }
            }

            Section {
                Label("Aucun serveur DevisMinute : votre compte et vos données restent sur cet iPhone. Les achats sont liés à votre identifiant Apple et se restaurent sur un nouvel appareil.", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
        }
        .appBackground()
        .navigationTitle("Mon compte")
        .confirmationDialog("Supprimer votre compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer le compte", role: .destructive) { accounts.deleteAccount() }
        } message: {
            Text("Votre compte est supprimé de cet appareil. Vos documents ne sont pas effacés et votre achat reste valable.")
        }
    }
}

/// Encart « Créer mon compte » de l'assistant de démarrage.
struct AccountSignUpSection: View {
    @Environment(AccountManager.self) private var accounts
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            if let account = accounts.account {
                Label(account.name.isEmpty ? "Compte créé" : "Compte créé : \(account.name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            } else {
                SignInWithAppleButton(.signUp, onRequest: { accounts.configure($0) }, onCompletion: { accounts.handle($0) })
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 46)
            }
        } header: {
            Text("Votre compte (facultatif)")
        } footer: {
            Text(accounts.lastError ?? "Créez votre compte avec votre identifiant Apple, sans mot de passe. Vous pouvez aussi continuer sans compte.")
        }
    }
}
