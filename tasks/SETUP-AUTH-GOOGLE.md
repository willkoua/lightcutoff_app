# Configuration — Connexion Google (Sign in with Google)

Le **code** de la connexion Google est intégré (branche `feat/auth-google`). Pour
qu'elle **fonctionne à l'exécution**, il reste une config **console Firebase +
empreintes** que seul toi peux faire. Tant que ce n'est pas fait, le bouton
« Continuer avec Google » échouera (`ApiException: 10` / `DEVELOPER_ERROR`).

App Android : **`com.njuka.app`** · Projet Firebase : **`lightcutoff-dev`**.

---

## 1. Activer le provider Google
Console Firebase → **Authentication → Sign-in method → Add new provider →
Google** → **Activer**, choisir l'**email de support** → Enregistrer.

## 2. Ajouter les empreintes SHA (indispensable sur Android)
Console Firebase → **Paramètres du projet → Tes applications → app Android
`com.njuka.app` → « Ajouter une empreinte »**. Ajoute **les trois** :

- **SHA-1 debug** (déjà calculée pour toi) :
  ```
  25:2B:F6:24:B0:4F:73:43:E5:3B:95:3D:AB:FE:FD:93:0D:18:2F:91
  ```
- **SHA-1 release** (depuis ton keystore `njuka-release.jks`) :
  ```bash
  keytool -list -v -alias njuka -keystore android/app/njuka-release.jks \
    | grep -i "SHA 1"
  ```
- **SHA-1 Play App Signing** ⚠️ **le plus oublié** : comme l'app installée
  depuis le **test interne** est resignée par Google (Play App Signing), il faut
  AUSSI ajouter l'empreinte de la **clé d'app** de Google, sinon Google Sign-in
  marche en local mais **échoue sur le build du Play Store**.
  Play Console → **Test et publication → Configuration → Intégrité de l'app →
  Clé de signature de l'app** → copier le **SHA-1** affiché → l'ajouter dans Firebase.

## 3. Régénérer `google-services.json`
Après avoir ajouté les empreintes : Firebase → Paramètres du projet → app
Android → **télécharger `google-services.json`** → remplacer
`android/app/google-services.json`. (C'est lui qui apporte le `oauth_client` /
`default_web_client_id` que `google_sign_in` lit automatiquement — **aucun code
Android à modifier**.)

Puis :
```bash
flutter clean && flutter pub get
flutter run --dart-define=APP_ENV=staging   # ou =dev
```

## 4. (Plus tard) iOS
Pour iOS il faudra ajouter le **reversed client ID** (depuis
`GoogleService-Info.plist`) dans `Info.plist` → `CFBundleURLSchemes`. Inutile
pour tester sur Android. (Rappel : si on offre du login social sur iOS, Apple
exige aussi **Sign in with Apple** — cf. plan auth dans `todo.md`.)

---

## Tester le flux
1. Écran de connexion → **« Continuer avec Google »** → choisir un compte.
2. **1er login** → écran **« Compléter mon profil »** : choisir un **pseudo
   unique** (prénom/nom préremplis depuis le compte Google) → **Terminer**.
3. Arrivée sur l'app (onglet Liste). Reconnexions suivantes → directement l'app.

## Dépannage
- **`ApiException: 10` / `DEVELOPER_ERROR`** → SHA-1 manquante ou
  `google-services.json` pas régénéré après l'ajout des empreintes.
- **Bouton qui « ne fait rien »** → souvent une annulation (pop-up fermée) :
  c'est silencieux par design (pas de message d'erreur).
- **Marche en local mais pas depuis le Play Store** → SHA-1 **Play App Signing**
  non ajoutée (étape 2, 3ᵉ empreinte).

---

## Ce qui est fait côté code (branche `feat/auth-google`)
- `google_sign_in` ajouté ; `AuthService.signInWithGoogle()` + `completeSocialProfile()`.
- Nouvel état `AuthStatus.profileIncomplete` + écran `CompleteProfileScreen`
  (un compte social sans pseudo est routé là avant d'entrer dans l'app).
- Bouton « Continuer avec Google » sur l'écran de connexion ; erreurs i18n FR/EN.
- `flutter analyze` clean · **141 tests** verts.
