import SwiftUI
import AuthenticationServices
import DevisCore

/// « Mon compte » : connexion avec Apple (facultative), version complète, déconnexion et suppression.
struct AccountView: View {
    @Environment(AccountManager.self) private var accounts
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmDelete = false
    @State private var method: Method = .email

    enum Method { case apple, email }

    var body: some View {
        List {
            if let online = accounts.online {
                Section {
                    HStack(spacing: Theme.Space.m) {
                        InitialsAvatar(name: online.email, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(online.email).font(.headline)
                            Label("Compte e-mail confirmé", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(Theme.success)
                        }
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
            } else if let account = accounts.account {
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
                        Text("Avec votre identifiant Apple ou avec votre adresse e-mail. Le compte est facultatif : l'application fonctionne entièrement sans.")
                            .font(.footnote).foregroundStyle(Theme.neutral)
                    }
                    .padding(.vertical, Theme.Space.xs)
                    Picker("Méthode", selection: $method) {
                        Text("Avec Apple").tag(Method.apple)
                        Text("Avec un e-mail").tag(Method.email)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    if method == .apple {
                        SignInWithAppleButton(.signUp, onRequest: { accounts.configure($0) }, onCompletion: { accounts.handle($0) })
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 48)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                } footer: {
                    if method == .apple, let error = accounts.lastError { Text(error).foregroundStyle(Theme.danger) }
                }
                if method == .email {
                    EmailAccountForm()
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
                        .disabled(accounts.isWorking)
                } footer: {
                    if let error = accounts.lastError {
                        Text(error).foregroundStyle(Theme.danger)
                    } else {
                        Text(accounts.online != nil
                             ? "La suppression efface votre compte de nos serveurs. Vos devis, factures et clients restent sur cet iPhone."
                             : "Vos devis, factures et clients restent sur cet iPhone. Pour retirer complètement l'accès, allez aussi dans Réglages › [votre nom] › Connexion et sécurité › Se connecter avec Apple.")
                    }
                }
            }

            Section {
                Label("Vos devis, factures et clients restent sur cet iPhone. Avec un compte e-mail, seuls votre adresse et votre mot de passe (chiffré) sont enregistrés en ligne, en Europe. Les achats sont liés à votre identifiant Apple.", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(Theme.neutral)
            }
        }
        .appBackground()
        .navigationTitle("Mon compte")
        .confirmationDialog("Supprimer votre compte ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer le compte", role: .destructive) { Task { await accounts.deleteAccount() } }
        } message: {
            Text(accounts.online != nil
                 ? "Votre compte e-mail est supprimé définitivement de nos serveurs. Vos documents restent sur cet iPhone et votre achat reste valable."
                 : "Votre compte est supprimé de cet appareil. Vos documents ne sont pas effacés et votre achat reste valable.")
        }
    }
}

/// Encart « Créer mon compte » de l'assistant de démarrage.
struct AccountSignUpSection: View {
    @Environment(AccountManager.self) private var accounts
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            if let name = accounts.displayName {
                Label("Compte créé : \(name)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            } else {
                SignInWithAppleButton(.signUp, onRequest: { accounts.configure($0) }, onCompletion: { accounts.handle($0) })
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 46)
                NavigationLink { AccountView() } label: { Label("Créer un compte avec mon e-mail", systemImage: "envelope") }
            }
        } header: {
            Text("Votre compte (facultatif)")
        } footer: {
            Text(accounts.lastError ?? "Avec votre identifiant Apple (sans mot de passe) ou votre adresse e-mail. Vous pouvez aussi continuer sans compte.")
        }
    }
}

/// Inscription et connexion par e-mail.
struct EmailAccountForm: View {
    @Environment(AccountManager.self) private var accounts
    @State private var hasAccount = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    enum Field { case email, password }

    var body: some View {
        Section {
            TextField("Adresse e-mail", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(.next)
                .onSubmit { focused = .password }
            SecureField(hasAccount ? "Mot de passe" : "Mot de passe (8 caractères, lettres et chiffres)", text: $password)
                .textContentType(hasAccount ? .password : .newPassword)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
            Button(action: submit) {
                if accounts.isWorking { ProgressView().frame(maxWidth: .infinity) } else {
                    Text(hasAccount ? "Se connecter" : "Créer mon compte").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .disabled(accounts.isWorking || email.isEmpty || password.isEmpty)
            Button(hasAccount ? "Pas encore de compte ? Créer un compte" : "J'ai déjà un compte : me connecter") {
                hasAccount.toggle()
                accounts.lastError = nil
            }
            .font(.footnote)
            if hasAccount {
                Button("Mot de passe oublié") { Task { await accounts.resetPassword(email: email) } }
                    .font(.footnote)
                    .disabled(email.isEmpty || accounts.isWorking)
            }
        } header: {
            Text(hasAccount ? "Connexion" : "Inscription")
        } footer: {
            if let error = accounts.lastError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).foregroundStyle(Theme.danger)
                    if error == AuthError.emailNotConfirmed.errorDescription {
                        Button("Renvoyer l'e-mail de confirmation") { Task { await accounts.resendConfirmation(email: email) } }
                    }
                }
            } else if let info = accounts.lastInfo {
                Text(info).foregroundStyle(Theme.success)
            } else {
                Text("Votre mot de passe est chiffré et n'est jamais visible, même par nous.")
            }
        }
    }

    private func submit() {
        focused = nil
        Task {
            if hasAccount {
                await accounts.signIn(email: email, password: password)
            } else {
                await accounts.signUp(email: email, password: password)
                if accounts.lastInfo != nil { hasAccount = true }
            }
            if accounts.online != nil { password = "" }
        }
    }
}
