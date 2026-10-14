# Sauvegardes : format, sécurité et restauration

Implémentation : `DevisMinuteKit/Sources/DevisCore/Backup/Backup.swift`. Tests : `DataServicesTests.swift` (`BackupTests`) et `DevisMinuteTests/DataStoreTests.swift`.

## Contenu

Une sauvegarde contient **toutes** les données : profil de l'entreprise, logo, clients, catalogue, devis, factures (avec paiements et sceaux d'intégrité), états et formats de numérotation, apparence des documents.

## Format du fichier

Fichier JSON (extension `.json`, nommé « Sauvegarde DevisMinute AAAA-MM-JJ ») :

```json
{
  "format": "devisminute-backup",
  "version": 1,
  "createdAt": 782136000,
  "documentCount": 42,
  "customerCount": 12,
  "encryption": {
    "algorithm": "AES-256-GCM",
    "kdf": "PBKDF2-HMAC-SHA256",
    "iterations": 600000,
    "salt": "base64…"
  },
  "payloadSHA256": "hex…",
  "payload": "base64…"
}
```

- `payload` : le contenu (`BackupSnapshot`) en JSON à clés triées ; s'il est chiffré, nonce (12 octets) + texte chiffré + étiquette d'authentification (16 octets).
- `payloadSHA256` : empreinte du contenu en clair, vérifiée à la restauration ; elle sert aussi de données authentifiées pour AES-GCM.
- Dates : secondes depuis le 1er janvier 2001 (représentation exacte des dates de l'application).
- Montants : nombres décimaux JSON ; à la lecture, ils sont normalisés à 6 décimales pour éliminer d'éventuels artefacts de conversion.

## Chiffrement

- Clé de 256 bits dérivée du mot de passe par PBKDF2-HMAC-SHA256, 600 000 itérations, sel aléatoire de 16 octets (implémentation vérifiée avec les vecteurs de test publiés).
- AES-256-GCM (CryptoKit) : confidentialité et détection de toute modification.
- Mot de passe : 8 caractères minimum. **Il n'existe aucun moyen de récupérer une sauvegarde sans son mot de passe.**
- Sans mot de passe, le fichier n'est pas chiffré : il contient des données personnelles et commerciales en clair. L'application propose le chiffrement par défaut.

## Restauration

1. Lecture de l'enveloppe : format et version reconnus, sinon refus.
2. Déchiffrement (mot de passe demandé si nécessaire) ; un mauvais mot de passe ou un fichier altéré est rejeté.
3. Vérification de l'empreinte SHA-256 du contenu.
4. Contrôles de cohérence : identifiants uniques, numéros de factures non vides et sans doublon (bloquants) ; sceaux de factures, références de clients (avertissements).
5. Récapitulatif affiché à l'utilisateur, qui confirme.
6. Remplacement de l'ensemble des données dans une seule transaction SwiftData.

Aucune donnée n'est modifiée avant l'étape 6.

## Recommandations à l'utilisateur

- Sauvegarder au moins une fois par mois, et après chaque série de factures.
- Conserver les fichiers hors de l'iPhone (iCloud Drive, ordinateur, clé USB), en plusieurs exemplaires.
- Conserver les sauvegardes et les PDF émis au moins 10 ans.
- Les exports CSV ne sont pas chiffrés : à transmettre avec précaution (par exemple via un lien protégé).
