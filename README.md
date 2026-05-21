# NJUKA

Application mobile de **signalement de coupures de courant** (Android & iOS), construite avec Flutter et Firebase. Les utilisateurs signalent les coupures dans leur zone (avec géolocalisation), confirment les coupures existantes et suivent leur résolution.

- **Nom de l'app** : NJUKA
- **Package / module** : `lightcutoff_app`
- **Identifiant** : `com.example.lightcutoff_app`
- **Plateformes** : Android, iOS uniquement
- **Projet Firebase** : `lightcutoff-dev`
- **Gestion d'état** : Provider
- **Modèle de données** : voir [`SCHEMA.md`](SCHEMA.md)

### État d'avancement

**MVP terminé ✅** — authentification + signalement de coupures, testé et livrable.

| Phase | Statut |
|-------|--------|
| Setup (projet, Firebase, CI, émulateurs) | ✅ Terminé |
| Phase 0 — Fondations (modèles, thème, squelette, règles) | ✅ Terminé |
| Phase 1 — Authentification (login, inscription, vérif. email, indicatif tél.) | ✅ Terminé |
| Phase 2 — Signalement (géoloc, liste temps réel, confirmation, résolution) | ✅ Terminé |
| Phase 3 — Finitions (tests automatisés, états UI) | ✅ Terminé |
| Post-MVP livré | 🗺️ carte · 👤 profil · 🔁 anti-doublon · 🔒 anonymat confirmations · 👋 onboarding · 🏛️ repository pattern |

Pistes restantes : notifications push FCM, photo de profil, filtres/recherche, job CI iOS.

---

## Prérequis

| Outil | Version utilisée | Installation |
|-------|------------------|--------------|
| Flutter SDK | 3.29.0 (Dart 3.7.0) | https://docs.flutter.dev/get-started/install |
| Java JDK | 17 | `brew install openjdk@17` |
| Xcode + CocoaPods | (iOS) | App Store + `sudo gem install cocoapods` |
| Android Studio + SDK | API 35 | https://developer.android.com/studio |
| Firebase CLI | 14.x | `npm install -g firebase-tools` |
| FlutterFire CLI | 1.3.x | `dart pub global activate flutterfire_cli` |

Contraintes natives déjà appliquées dans le projet :
- **Android** : `minSdk = 23` (requis par `cloud_functions`) — voir `android/app/build.gradle.kts`
- **Android** : plugin Kotlin `2.1.0` (requis par les dépendances de `geolocator`) — voir `android/settings.gradle.kts`
- **iOS** : `platform :ios, '13.0'` (requis par les SDK Firebase) — voir `ios/Podfile`

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

Le projet est **déjà connecté** à Firebase (`lightcutoff-dev`). Les fichiers générés sont versionnés :
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

L'initialisation se fait dans `lib/main.dart` via `Firebase.initializeApp(...)`.

### Re-générer la config (si besoin)

Nécessite d'être authentifié sur le compte Firebase qui possède le projet (`willkoua@gmail.com`) :

```bash
firebase login            # ou: firebase login --reauth
flutterfire configure --project=lightcutoff-dev --platforms=android,ios
```

> Sur macOS avec le Ruby système, FlutterFire a besoin du gem `xcodeproj` pour iOS :
> `gem install --user-install xcodeproj`

### Packages principaux

- **Firebase** : `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_database`, `cloud_functions`
- **État** : `provider`
- **Géolocalisation** : `geolocator`, `geocoding`
- **UI** : `intl_phone_field` (champ téléphone avec indicatif)

---

## Authentification

Flux géré par `AuthProvider` + `AuthGate`. Trois états :

| État | Écran affiché |
|------|---------------|
| Non connecté | Login (`login_screen.dart`) |
| Connecté, email non vérifié | Vérification (`email_verification_screen.dart`) |
| Connecté, email vérifié | Home (`home_screen.dart`) |

- **Inscription** : crée le compte Auth + le doc `users/{uid}` dans Firestore, puis envoie un email de vérification.
- **Vérification email obligatoire** : l'accès à l'app est bloqué tant que l'email n'est pas confirmé.
  - En **production** : un vrai email est envoyé.
  - Avec les **émulateurs** : aucun email réel — récupérer le lien dans l'Emulator UI (Auth) ou via
    `curl http://localhost:9099/emulator/v1/projects/lightcutoff-dev/oobCodes`.
- **Téléphone** : champ avec sélecteur d'indicatif international (`intl_phone_field`), défaut Cameroun (+237). Le numéro est stocké au format complet (`+237...`).
- **Compte désactivé** : un utilisateur dont le profil a `status: disabled` est déconnecté avec un message.

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

### Choisir l'environnement Firebase (en ligne ou émulateurs)

L'app se connecte par défaut à **Firebase en ligne** (`lightcutoff-dev`). Pour la
faire tourner contre les **émulateurs locaux**, passer le flag `USE_EMULATOR` :

```bash
# Firebase en ligne (par défaut)
flutter run

# Émulateurs Firebase locaux (Auth + Firestore + Database)
flutter run --dart-define=USE_EMULATOR=true
```

- L'hôte est résolu automatiquement : `10.0.2.2` sur émulateur Android, `localhost` sinon.
- Override possible : `--dart-define=EMULATOR_HOST=192.168.x.x` (ex. appareil physique).
- Pense à démarrer les émulateurs avant (`firebase emulators:start`).

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

> Pour faire pointer l'app vers ces émulateurs, lancer l'app avec `--dart-define=USE_EMULATOR=true`
> (voir « Choisir l'environnement Firebase » plus haut). Par défaut l'app utilise Firebase en ligne.

> ⚠️ **Android & HTTP en clair** : les émulateurs communiquent en HTTP (non chiffré), bloqué par défaut sur Android.
> Une config réseau **debug-only** l'autorise pour `10.0.2.2`/`localhost`
> ([`android/app/src/debug/res/xml/network_security_config.xml`](android/app/src/debug/res/xml/network_security_config.xml)).
> Les builds release restent en HTTPS strict.

---

## Build de production

```bash
# Android (APK)
flutter build apk --release

# Android (App Bundle pour le Play Store)
flutter build appbundle --release

# iOS
flutter build ipa --release
```

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
  ├── main.dart            # point d'entrée + init Firebase + bascule émulateurs
  ├── app.dart             # MaterialApp, thème, MultiProvider
  ├── firebase_options.dart
  ├── config/              # config d'environnement (USE_EMULATOR, hôte, ports)
  ├── models/              # modèles de données + enums (voir SCHEMA.md)
  ├── repositories/        # contrats abstraits (AuthRepository, ReportRepository…)
  ├── services/            # implémentations concrètes (Firebase/geolocator)
  ├── providers/           # gestion d'état (ChangeNotifier : AuthProvider…)
  ├── screens/             # écrans / pages
  ├── widgets/             # composants réutilisables
  ├── theme/               # couleurs + ThemeData (charte graphique)
  └── utils/               # helpers (validators, formatting…)
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
          flutter-version: '3.29.0'
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
│   ├── main.dart              # Point d'entrée + init Firebase + bascule émulateurs
│   ├── app.dart               # MaterialApp, thème, MultiProvider
│   ├── firebase_options.dart  # Config Firebase (généré)
│   ├── config/                # AppConfig (USE_EMULATOR, hôte, ports)
│   ├── models/                # AppUser, Report, Confirmation, enums, geo
│   ├── repositories/          # interfaces Auth/Report/Location
│   ├── services/              # implémentations Firebase/geolocator
│   ├── providers/             # AuthProvider, ReportProvider
│   ├── screens/               # onboarding, login, register, home, carte, profil, détail
│   ├── widgets/               # report_card, location_permission_sheet
│   ├── theme/                 # AppColors, AppTheme (charte graphique)
│   └── utils/                 # validators, formatting
├── android/                   # Projet Android (minSdk 23, Kotlin 2.1.0)
│   └── app/src/debug/         # config réseau debug (cleartext émulateurs)
├── ios/                       # Projet iOS (platform 13.0)
├── firebase.json              # Config FlutterFire + Firestore + émulateurs
├── firestore.rules            # Règles de sécurité Firestore
├── .firebaserc                # Projet Firebase par défaut
├── SCHEMA.md                  # Modèle de données (collections, champs, règles)
└── pubspec.yaml               # Dépendances
```
