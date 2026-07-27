# NJUKA

Application mobile de **signalement de coupures de service public — électricité et eau** (Android & iOS), construite avec Flutter et Firebase. Les utilisateurs signalent les coupures dans leur zone (géolocalisées), confirment celles existantes, déclarent le retour du service, suivent la résolution — et consultent les **coupures planifiées officielles** de leur fournisseur d'électricité (Eneo au Cameroun).

**Auth-light** (pivot 2026-06-24) : la lecture, le signalement et le vote sont accessibles **sans inscription** via Firebase Anonymous Auth ; la création d'un compte (profil, statistiques, suivi de quartier, notifications) reste optionnelle et **préserve l'historique anonyme** via `linkWithCredential`.

- **Nom de l'app** : NJUKA — *« Ensemble, on y voit plus clair. »*
- **Package / module** : `lightcutoff_app`
- **Identifiant** : `com.njuka.app` (Android & iOS — figé, 1ʳᵉ publication faite)
- **Plateformes** : Android, iOS uniquement
- **Éditeur** : Bogal Consulting
- **Gestion d'état** : Provider
- **Modèle de données** : voir [`SCHEMA.md`](SCHEMA.md)

### Environnements

L'app a **3 environnements**, choisis au build via `--dart-define=APP_ENV=…` :

| Env | Firebase | Outils dev (sélecteurs langue, pays/compagnie) | Bannière |
|-----|----------|------------------------------------------------|----------|
| `dev` | Émulateurs locaux | ✅ visibles | `DEV` |
| `staging` | **`lightcutoff-dev`** (en ligne) | ✅ visibles, même en release | `STAGING` |
| `prod` | **`njuka-prod`** (Firestore europe-west2) | ❌ cachés | aucune |

Sans `APP_ENV` → `staging` (comportement historique) ; `USE_EMULATOR=true` → `dev` (alias hérité). Avant un build **prod**, basculer les configs natives avec `tool/use_env.sh prod` (Google Sign-In natif lit `google-services.json` / `GoogleService-Info.plist`) — puis revenir avec `tool/use_env.sh staging`. Config : [`lib/config/app_config.dart`](lib/config/app_config.dart).

### État d'avancement

**MVP+ complet** — en **test fermé Play Store** (release `1.2.0+55` déployée ; `1.2.0+57` = migration API 36, buildée). **iOS** : premier build `1.2.0 (57)` uploadé sur App Store Connect (TestFlight). **Prod `njuka-prod`** créée et validée de bout en bout, publication à déclencher.

| Domaine | Livré |
|---------|-------|
| Authentification | **Anonymous Auth par défaut** (lecture/signalement/vote sans inscription) ; connexion **Google / Facebook / Apple (iOS)** = **liaison à la session anonyme** (`linkWithCredential` → uid et historique préservés) ; login pseudo **ou** email, vérif. email (provider `password` uniquement), **pseudo auto-généré** à la création (personnalisable **une seule fois**, verrou serveur), mot de passe oublié, changement email/mdp, **suppression de compte RGPD** |
| Multi-service | **électricité + eau** (`ServiceType { electricity, water }`) — sélecteur formulaire, chips couleurs, marqueurs carte différenciés, filtre liste/carte/stats persistant |
| Signalements | géoloc + reverse-geocoding, liste temps réel **paginée**, filtres/tri/recherche, anti-doublon 500 m, médias photo/GIF |
| Crowd | **confirmations** & **« courant revenu »** (1 vote/uid, transactionnel — y compris anonyme, **indicateur « tu as déjà voté »**), **auto-résolution** par seuil, archivage soft-delete + purge 30 j |
| Statistiques | écran perso **« mes coupures »** + **« ma zone »** (compte, durées, répartition heure/jour), **splittables par service** — agrégats anonymes |
| Mesure | **Firebase Analytics** (funnel : `anonymous_started` → `anonymous_first_report` → `upgrade_started` → `upgrade_completed` + signalement/confirmation/restauration + screen views), collecte coupée en dev |
| Coupures officielles | **programme Eneo ingéré quotidiennement** (Cloud Function) → segment « Programmées » (recherche quartier + filtre région), **suivre un quartier** + alerte push la veille |
| Multi-pays | fournisseurs résolus automatiquement (profil → locale → défaut), registre extensible ([`lib/config/utilities.dart`](lib/config/utilities.dart) — `Utility { id, service, country, … }` unifié élec/eau) |
| Carte | `flutter_map` + tuiles Stadia Maps (repli OSM) + clustering + marqueurs par service |
| Incitations | **prompt d'ouverture « Chez toi aussi ? »** (coupure <1 km : confirmer / **démentir** `denials` / passer), **vote 1-tap depuis la notification** (boutons Oui/Non, vote en arrière-plan sans ouvrir l'app), **notification de rétablissement** à l'auteur + confirmeurs |
| Notifications | FCM **data-only** pilotées par les **confirmations** (rayon 500 m d'extension de proche en proche, dédup 1 notif/user/report, position exacte à lecture verrouillée admin/owner), préférence opt-out, **N/A en anonyme** |
| i18n | **FR / EN** complet (UI + erreurs), ARB + `flutter gen-l10n` |
| Hors-ligne | persistance Firestore + bandeau global « Hors ligne », écran « Réessayer » dédié si Anonymous Auth échoue au démarrage |
| Qualité | App Check, Crashlytics, règles Firestore/Storage **testées** (compteurs durcis : +1 lié au vote ; `!isAnonymous()` sur `users`/`usernames`/`devices` ; verrou changement de pseudo), CI 3 jobs, **210 tests Dart** + 21 tests functions + tests de règles |

Pistes restantes : bot WhatsApp (spec `tasks/SPEC-WHATSAPP-BOT.md`), prédiction de délestage, photo de profil, ingestion CAMWATER (eau).

---

## Prérequis

| Outil | Version utilisée | Installation |
|-------|------------------|--------------|
| Flutter SDK | 3.44.7 (Dart 3.12) | https://docs.flutter.dev/get-started/install |
| Java JDK | 17 | `brew install openjdk@17` |
| Xcode + CocoaPods | 26.x (iOS) | App Store + `sudo gem install cocoapods` |
| Android Studio + SDK | API 36 | https://developer.android.com/studio |
| Firebase CLI | 14.x | `npm install -g firebase-tools` |
| FlutterFire CLI | 1.3.x | `dart pub global activate flutterfire_cli` |

Contraintes natives déjà appliquées dans le projet :
- **Android** : `minSdk = 23` (requis par `cloud_functions`), `compileSdk`/`targetSdk = 36` (exigence Play 2026-08-31) — voir `android/app/build.gradle.kts`
- **Android** : plugin Kotlin `2.1.0` (requis par les dépendances de `geolocator`) — voir `android/settings.gradle.kts`
- **iOS** : `platform :ios, '15.0'` (requis par les SDK Firebase récents) — voir `ios/Podfile`

> Si `flutterfire`/`firebase` ne sont pas dans le PATH, ajoute :
> `export PATH="$PATH:$HOME/.pub-cache/bin"`

---

## Installation

```bash
cd lightcutoff_app

# 1. Récupérer les dépendances Dart/Flutter
flutter pub get

# 2. (iOS uniquement) installer les pods
cd ios && pod install && cd ..

# 3. Vérifier que tout est OK
flutter doctor
flutter analyze
```

---

## Configuration Firebase

Les environnements **dev** et **staging** partagent le projet `lightcutoff-dev` ; **prod** utilise `njuka-prod` (alias `staging` et `prod` dans `.firebaserc`). Les fichiers générés sont versionnés :
- `lib/firebase_options.dart` (staging) + `lib/firebase_options_prod.dart` (prod)
- `android/app/google-services.json` (+ `google-services.prod.json`, gitignoré)
- `ios/Runner/GoogleService-Info.plist` (+ `GoogleService-Info.prod.plist`, gitignoré)

L'initialisation se fait dans `lib/main.dart` via `Firebase.initializeApp(...)` : les options sont choisies selon `AppConfig.isProd`. Pour un build prod, basculer d'abord les configs natives avec `tool/use_env.sh prod` (staging reste la config par défaut versionnée).

> ⚠️ **Google Sign-In prod** : les clients OAuth Android sont encore tenus par `lightcutoff-dev` (contrainte Google : un seul projet par combinaison package + SHA). La bascule (« jour J ») est documentée dans `tasks/todo.md`.

### Re-générer la config (si besoin)

Nécessite d'être authentifié sur le compte Firebase qui possède le projet (`willkoua@gmail.com`) :

```bash
firebase login            # ou: firebase login --reauth
flutterfire configure --project=lightcutoff-dev --platforms=android,ios
```

> Sur macOS avec le Ruby système, FlutterFire a besoin du gem `xcodeproj` pour iOS :
> `gem install --user-install xcodeproj`

### Packages principaux

- **Firebase** : `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_database`, `cloud_functions`, `firebase_storage`, `firebase_messaging`, `firebase_app_check`, `firebase_crashlytics`
- **État** : `provider`
- **Géolocalisation** : `geolocator`, `geocoding`
- **Carte** : `flutter_map`, `flutter_map_marker_cluster`, `latlong2` (tuiles Stadia Maps via `--dart-define=STADIA_API_KEY`)
- **UI / divers** : `intl_phone_field`, `image_picker`, `flutter_local_notifications`, `url_launcher`, `connectivity_plus`, `shared_preferences`
- **Tests** : `mocktail`, `fake_cloud_firestore`, `firebase_auth_mocks`

---

## Authentification

Flux géré par `AuthProvider` + `AuthGate`. **6 états** depuis le pivot 2026-06-24 :

| État | Quand | Écran affiché |
|------|-------|---------------|
| `unknown` | Init, ou attente de `signInAnonymously` | `SplashScreen` |
| `anonymous` | Session Firebase Anonymous Auth (défaut au 1ᵉʳ lancement) | `MainShell` (Home/Map/Profil) — mur d'upgrade côté Profil |
| `awaitingVerification` | Compte email créé, email non vérifié (**provider `password` uniquement** — les emails sociaux sont réputés vérifiés) | `EmailVerificationScreen` |
| `profileIncomplete` | Login social sans profil **et** échec de l'auto-création | `CompleteProfileScreen` (repli — le profil est normalement créé automatiquement avec un pseudo généré) |
| `authenticated` | Compte vérifié + profil chargé | `MainShell` |
| `unauthenticated` | `signInAnonymously` a échoué (offline / Anonymous Auth pas activé) | `AnonymousRetryScreen` (« Réessayer » + « J'ai déjà un compte ») |

- **Lecture / signalement / vote** : possibles dès `anonymous` (uid présent, App Check + règles `castsVote` intactes). **Aucune référence à l'auteur** n'est affichée sur les reports anonymes.
- **Upgrade email** : depuis le mur du Profil → `UpgradeAccountScreen` → `auth.upgradeWithEmail(...)` (`linkWithCredential` → uid préservé → tous les reports/votes anonymes restent attachés). Bascule auto vers `awaitingVerification`.
- **Connexion sociale (Google / Facebook / Apple)** : quand la session est anonyme, c'est une **liaison** (`linkWithCredential`/`linkWithProvider`) → même uid, historique préservé. Repli en connexion classique uniquement si le compte social appartient déjà à un autre utilisateur (`credential-already-in-use`). Un dialog d'avertissement ne s'affiche que si la session anonyme a une activité réelle (`lib/utils/anonymous_activity.dart`).
- **Pseudo** : généré automatiquement à la création (`prenom_NNN`, `lib/utils/username_generator.dart`), personnalisable **une seule fois** (champ `usernameChangesLeft`, verrou dans les règles Firestore).
- **Inscription classique** (sans passer par l'anonyme) : reste disponible via « J'ai déjà un compte » → `LoginScreen` → `RegisterScreen`.
- **Vérification email obligatoire** : pour les comptes réels uniquement (pas en anonyme). Avec les émulateurs : récupérer le lien dans l'Emulator UI (Auth) ou via `curl http://localhost:9099/emulator/v1/projects/lightcutoff-dev/oobCodes`.
- **Téléphone** : champ avec sélecteur d'indicatif international (`intl_phone_field`), défaut Cameroun (+237).
- **Reset session anonyme** : Paramètres → « Effacer cette session anonyme » → `signOut` + nouvelle session anonyme. **Réinstaller l'app = nouvel uid anonyme** (perte de l'historique device — limite acceptée v1, mitigée par App Check).
- **Compte désactivé** : un utilisateur dont le profil a `status: disabled` est déconnecté avec un message.

> ⚠️ Anonymous Auth doit être activé côté console Firebase (`lightcutoff-dev` → Authentication → Sign-in method → Anonymous). Sinon `signInAnonymously` renvoie `admin-restricted-operation` et l'app reste sur `AnonymousRetryScreen`.

---

## Lancer l'application

### Lister les appareils / émulateurs

```bash
flutter devices
flutter emulators
```

### Android

```bash
flutter emulators --launch Medium_Phone_API_35
flutter run -d emulator-5554
```

### iOS

```bash
open -a Simulator
flutter run
```

Pendant l'exécution (`flutter run`) : `r` = hot reload, `R` = hot restart, `q` = quitter.

### Choisir l'environnement (dev / staging / prod)

```bash
# dev — émulateurs Firebase locaux + outils dev + bannière DEV
flutter run --dart-define=APP_ENV=dev

# staging — Firebase en ligne (lightcutoff-dev) + outils dev + bannière STAGING
flutter run --dart-define=APP_ENV=staging
flutter run                                  # équivalent (défaut = staging)

# prod — Firebase njuka-prod, sans bannière ni outils dev (tool/use_env.sh prod d'abord)
flutter run --dart-define=APP_ENV=prod
```

- La **clé Stadia** est nécessaire pour la carte : ajouter `--dart-define=STADIA_API_KEY=…` (sinon repli OSM, acceptable en dev).
- En `dev`, l'hôte des émulateurs est résolu automatiquement : `10.0.2.2` sur émulateur Android, `localhost` sinon. Override : `--dart-define=EMULATOR_HOST=192.168.x.x` (appareil physique). Démarrer les émulateurs avant (`firebase emulators:start`).
- Les **outils dev** dans Paramètres (sélecteur de langue, sélecteurs pays/compagnie **par service** — un champ Électricité + un champ Eau avec auto-coupling symétrique sur le pays) sont visibles en dev **et** staging, jamais en prod.

Config : [`lib/config/app_config.dart`](lib/config/app_config.dart), branchement dans [`lib/main.dart`](lib/main.dart).

---

## Émulateurs Firebase (Local Emulator Suite)

Config dans `firebase.json` / `.firebaserc`.

```bash
# Lancement simple (données perdues à l'arrêt)
firebase emulators:start
```

### Persistance des données

Par défaut, les données des émulateurs sont **perdues** à chaque arrêt. Pour les conserver, utiliser `--import` (charge les données au démarrage) et `--export-on-exit` (les sauvegarde à l'arrêt) vers un même dossier :

```bash
# 1. Tout premier lancement : crée le dossier d'export à l'arrêt (Ctrl+C)
firebase emulators:start --export-on-exit=./emulator-data

# 2. Lancements suivants : importe au démarrage ET ré-exporte à l'arrêt
firebase emulators:start --import=./emulator-data --export-on-exit=./emulator-data
```

> - Arrête toujours les émulateurs proprement avec **Ctrl+C** : l'export ne se fait qu'à un arrêt propre.
> - Sauvegarde manuelle pendant que les émulateurs tournent : `firebase emulators:export ./emulator-data`
> - Le dossier `emulator-data/` ne doit **pas** être versionné (déjà ajouté au `.gitignore`).

| Service | Port |
|---------|------|
| Emulator UI | http://localhost:4000 |
| Auth | 9099 |
| Firestore | 8080 |
| Realtime Database | 9000 |

Les règles de sécurité Firestore ([`firestore.rules`](firestore.rules)) sont chargées automatiquement par l'émulateur.

> Pour faire pointer l'app vers ces émulateurs, lancer l'app en **environnement dev** :
> `--dart-define=APP_ENV=dev` (voir « Choisir l'environnement » plus haut). Par défaut (`staging`)
> l'app utilise Firebase en ligne (`lightcutoff-dev`).

> ⚠️ **Android & HTTP en clair** : les émulateurs communiquent en HTTP (non chiffré), bloqué par défaut sur Android.
> Une config réseau **debug-only** l'autorise pour `10.0.2.2`/`localhost`
> ([`android/app/src/debug/res/xml/network_security_config.xml`](android/app/src/debug/res/xml/network_security_config.xml)).
> Les builds release restent en HTTPS strict.

---

## Build de production

Toujours passer `APP_ENV` **et** la clé Stadia pour un artefact publiable.

```bash
STADIA=<clé Stadia Maps>

# Android (App Bundle pour le Play Store) — staging pour le test fermé
flutter build appbundle --release \
  --dart-define=APP_ENV=staging --dart-define=STADIA_API_KEY=$STADIA

# Android (APK)
flutter build apk --release --dart-define=APP_ENV=staging --dart-define=STADIA_API_KEY=$STADIA

# iOS
flutter build ipa --release --dart-define=APP_ENV=staging --dart-define=STADIA_API_KEY=$STADIA

# PROD (Android ou iOS) : basculer les configs natives avant, revenir après
tool/use_env.sh prod
flutter build appbundle --release --dart-define=APP_ENV=prod --dart-define=STADIA_API_KEY=$STADIA
tool/use_env.sh staging
```

> L'AAB de release est signé `CN=Bogal Consulting` (keystore `android/app/njuka-release.jks`, `android/key.properties` — tous deux gitignorés). Checklist de publication prod dans `tasks/todo.md` (« Reste avant publication prod »).

---

## Tests

Les tests vivent dans le dossier `test/` (et `integration_test/` pour les tests d'intégration).

```bash
# Lancer tous les tests unitaires & widget
flutter test

# Avec rapport de couverture (génère coverage/lcov.info)
flutter test --coverage

# Un seul fichier
flutter test test/widget_test.dart

# Tests d'intégration sur un appareil/émulateur
flutter test integration_test/
```

Types de tests :
- **Unitaires** — logique pure (modèles, services), sans UI. Fichiers `*_test.dart`.
- **Widget** — un widget isolé via `testWidgets` + `WidgetTester`.
- **Intégration** — l'app complète sur un vrai appareil/émulateur (`package:integration_test`).

> Pour les tests touchant Firebase, brancher l'app sur le Local Emulator Suite (voir section dédiée) plutôt que sur le projet cloud.

---

## Conventions de code

- **Lint** : le projet utilise `flutter_lints` via `analysis_options.yaml`. Aucune erreur ne doit subsister.
  ```bash
  flutter analyze        # doit afficher "No issues found"
  dart format .          # formatage automatique (avant chaque commit)
  ```
- **Formatage** : `dart format` (indentation 2 espaces, largeur 80) — standard Dart, non négociable.
- **Nommage** :
  - Fichiers / dossiers : `snake_case` (ex. `home_page.dart`)
  - Classes / enums / types : `UpperCamelCase`
  - Variables / fonctions : `lowerCamelCase`
  - Constantes : `lowerCamelCase` (pas de `SCREAMING_CASE` en Dart)
- **Organisation de `lib/`** :
  ```
  lib/
  ├── main.dart            # point d'entrée + init Firebase + garde prod + bascule émulateurs
  ├── app.dart             # MaterialApp, thème, MultiProvider, bannière d'env
  ├── firebase_options.dart
  ├── config/              # AppConfig (APP_ENV, hôte, ports), AppConstants, utilities (Eneo/CAMWATER)
  ├── l10n/                # ARB FR/EN → généré dans l10n/generated/ (gitignoré)
  ├── models/              # modèles de données + enums (ServiceType, voir SCHEMA.md)
  ├── repositories/        # contrats abstraits (AuthRepository, ReportRepository, OfficialOutage…)
  ├── services/            # implémentations concrètes (Firebase/geolocator)
  ├── providers/           # gestion d'état (Auth, Report, Locale, Connectivity, Region, Stats…)
  ├── screens/             # écrans / pages (anonymous_retry, upgrade_account…)
  ├── widgets/             # composants (service_filter_bar, anonymous_first_report_sheet…)
  ├── theme/               # couleurs + ThemeData (charte graphique, AppColors.water)
  └── utils/               # helpers (validators, formatting, l10n_helpers, service_visuals…)
  ```
- **Architecture en couches** : `Provider → Repository (interface) → Service (impl) → Firebase`.
  Les providers dépendent des **interfaces** (`repositories/`), pas des implémentations
  concrètes (`services/`). Cela facilite les tests (on mocke l'interface) et un
  éventuel changement de backend (on fournit une nouvelle implémentation).
- **Imports** : préférer les imports relatifs au sein de `lib/`, et grouper Dart / Flutter / packages / projet.

---

## CI/CD

Pipeline d'intégration continue avec **GitHub Actions** : vérifie le formatage, l'analyse statique, les tests et le build à chaque push / PR.

Le workflow est déjà en place dans [`.github/workflows/ci.yml`](.github/workflows/ci.yml) :

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.7'
          channel: stable
          cache: true

      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --coverage

      # Build APK (debug) pour valider la compilation Android
      - run: flutter build apk --debug
```

> Le build iOS nécessite un runner macOS (`runs-on: macos-latest`) avec `pod install` — à ajouter dans un job séparé si besoin.

---

## Structure

```
lightcutoff_app/
├── lib/
│   ├── main.dart              # Point d'entrée + init Firebase + garde prod + émulateurs
│   ├── app.dart               # MaterialApp, thème, MultiProvider, bannière d'env
│   ├── firebase_options.dart  # Config Firebase (généré)
│   ├── config/                # AppConfig (3 envs), AppConstants, utilities (Eneo + CAMWATER)
│   ├── l10n/                  # ARB FR/EN (généré dans l10n/generated/, gitignoré)
│   ├── models/                # AppUser, Report (+serviceType), Confirmation, OfficialOutage, enums
│   ├── repositories/          # interfaces Auth/Report/Location/OfficialOutage
│   ├── services/              # implémentations Firebase/geolocator
│   ├── providers/             # Auth, Report, Locale, Connectivity, Region (+ serviceFilter), Stats, OfficialOutage
│   ├── screens/               # onboarding, login, home, carte, profil, settings, anonymous_retry, upgrade_account…
│   ├── widgets/               # report_card, service_filter_bar, anonymous_first_report_sheet, official_outage…
│   ├── theme/                 # AppColors (+water), AppTheme (charte graphique)
│   └── utils/                 # validators, formatting, l10n_helpers, geohash, service_visuals
├── functions/                 # Cloud Functions (Node 22, TS) — FCM, ingestion Eneo, RGPD
│   └── src/sources/           # adaptateurs fournisseurs (eneo.ts) — multi-pays
├── android/                   # Projet Android (minSdk 23, Kotlin 2.1.0)
│   └── app/src/debug/         # config réseau debug (cleartext émulateurs)
├── ios/                       # Projet iOS (platform 15.0, Xcode 26)
├── public/                    # pages légales (privacy, cgu, account-deletion, support) — Firebase Hosting
├── rules_tests/               # tests des règles Firestore/Storage (émulateur)
├── tool/                      # use_env.sh (bascule configs natives staging ↔ prod)
├── firebase.json              # Config FlutterFire + Firestore + Functions + Hosting + émulateurs
├── firestore.rules            # Règles de sécurité Firestore
├── firestore.indexes.json     # Index composites (pays + date)
├── .firebaserc                # Alias projets : staging → lightcutoff-dev, prod → njuka-prod
├── SCHEMA.md                  # Modèle de données (collections, champs, règles)
└── pubspec.yaml               # Dépendances
```
