# NJUKA — État du programme (plan détaillé fait / non fait)

> Audit basé sur le **code réel** (pas sur CONTEXT.md, qui date du 22 mai et est en
> retard sur les faits). Vérifié le 2026-06-03. `flutter analyze` clean, **70 tests verts**.

---

## ✅ FAIT (vérifié dans le code)

### Authentification & profil
- [x] Inscription (prénom, nom, **pseudo unique**, email, mot de passe, tél. avec indicatif, date de naissance)
- [x] Connexion par **pseudo OU email** + mot de passe
- [x] Vérification email obligatoire (gate bloquant tant que non vérifié)
- [x] Changement email / mot de passe (ré-authentification)
- [x] Édition de profil (nom, tél., date naissance, zone de résidence)
- [x] Désactivation de compte (`status: disabled` → déconnexion forcée)
- [x] Collection `usernames/{username}` (résolution pseudo→email, anti-énumération)

### Signalements (cœur métier)
- [x] Création d'un signalement géolocalisé (position + reverse-géocodage)
- [x] Liste temps réel + **pagination** (scroll infini, `reportsPageSize = 20`)
- [x] Filtres : statut, type, « mes signalements », **« à proximité »**, recherche texte, tri
- [x] **Confirmations** (1 vote/user, sous-collection, compteur transactionnel)
- [x] **Restorations** « courant revenu » (1 vote/user, auteur inclus)
- [x] **Auto-résolution** via Cloud Function `onRestorationCreated` (seuil `max(minVotes, ceil(confirms×ratio))`)
- [x] **Archivage** (soft-delete `archivedAt`, auteur uniquement) + purge cron 30 j
- [x] Anti-doublon : `findNearbyOngoing` (rayon 500 m) propose de confirmer plutôt que recréer
- [x] Média joint (GIF/JPEG/PNG), images redimensionnées ≤ 1280 px, plafond 8 Mo

### Carte
- [x] `flutter_map` (OpenStreetMap) + clustering (`flutter_map_marker_cluster`)
- [x] FAB « Signaler » + marqueurs cliquables → détail

### Proximité (geohash)
- [x] Encodeur geohash + voisines + couverture (`lib/utils/geohash.dart`, pur Dart)
- [x] `geohash` stocké sur chaque report
- [x] Filtre « à proximité » = requête Firestore bornée (centre + 8 voisines) affinée par distance
- [x] Refresh geohash device à la création + pull-to-refresh

### Notifications push (FCM)
- [x] Modèle `Device`, règles `devices`, constantes, channel Android
- [x] Token + persistance device (idempotent, upsert par token)
- [x] Réception foreground / background / app tuée + navigation vers le détail
- [x] Préférence « recevoir les alertes » (toggle sans désinscription)
- [x] **4 Cloud Functions** : `onReportCreated` (envoi), `onRestorationCreated`, `purgeArchivedReports`, `purgeStaleDevices`
- [x] Cloud Functions sur **Node 22 / firebase-functions v7 / admin v13**

### Onboarding & i18n
- [x] Onboarding 4 slides + gate (SharedPreferences `onboarding_seen`)
- [x] **i18n FR/EN** : toute l'UI traduite (écrans + widgets), splash + onboarding inclus
- [x] Migration `synthetic-package: false` → `lib/l10n/generated/` (gitignoré)
- [x] Helpers `l10n_helpers.dart` + validators en extension sur `AppLocalizations`
- [x] Sélecteur de langue (Paramètres, **debug only**)

### Sécurité & qualité
- [x] Règles Firestore + Storage + **tests de règles** (`rules_tests/`)
- [x] Crashlytics (collecte hors debug)
- [x] **CI 3 jobs** : Flutter (format/analyze/test/build apk) · **iOS build sans signature (macos-latest)** · Règles
- [x] 70 tests (modèles, utils, providers via mocktail des interfaces)

---

## ❌ NON FAIT / PARTIEL (par priorité)

### 🔴 Bloquants pour une mise en production / store
- [ ] **iOS APNs** : aucun fichier `.entitlements`, clé APNs absente → **les push ne marchent pas sur iOS**.
      *Différé : en attente de l'accès Apple Developer.*
- [ ] **Signing release Android** : `build.gradle.kts` signe encore avec les **clés debug**
      (`TODO` ligne 43-45) → **impossible de publier sur le Play Store**. Créer un keystore + config release.
- [ ] **Pages légales** (Politique de confidentialité / CGU / À propos) : exigées par les stores.
      *Différé explicitement (« pas maintenant »).*

### 🟠 Important (qualité / robustesse)
- [x] **i18n des messages d'erreur providers/services** ✅ FAIT.
      Nouvel enum `AppError` (`lib/models/app_error.dart`) renvoyé par la couche data
      (`auth_provider`, `report_provider`, `location_service`/`LocationException`), traduit
      côté UI via `appErrorLabel(context, code)` (`l10n_helpers.dart`). 18 clés `errorXxx`
      ajoutées FR/EN. Tous les SnackBars d'erreur sont désormais localisés. 70 tests verts.
- [ ] **Fournisseur de tuiles carte à clé** : on tape directement `tile.openstreetmap.org`
      (sans clé) → fragile en prod (politique d'usage OSM, pas de SLA). Passer à un fournisseur à clé
      (MapTiler/Stadia/Thunderforest).
- [~] **Firebase App Check** — client intégré ✅ (commit `c056703` : `firebase_app_check`,
      `activate()` dans `main.dart` : Play Integrity / AppAttest+DeviceCheck / debug provider).
      Enforcement console = **« Non appliqué » partout** (vérifié sur screenshot) → aucun outage.

      **À FAIRE MAINTENANT (cheap, sans Apple) — ✅ TERMINÉ :**
      - [x] App **Android** enregistrée dans App Check (Play Integrity + SHA-256 debug
            `5A:F9:…:8B:10`).
      - [x] **Debug token** capturé sur le Samsung S916W (via logcat `DebugAppCheckProvider`)
            et enregistré en console (« Gérer les jetons de débogage »). Token = secret, hors Git.
            ⚠️ régénéré si réinstall/effacement des données → à ré-enregistrer.
      - [x] **Enforcement laissé OFF** (volontaire).

      **DIFFÉRÉ — lot « iOS / Apple » (bloqué sur accès Apple Developer, même blocant qu'APNs) :**
      - [ ] Enregistrer l'**app iOS** (App Attest) + uploader la **clé DeviceCheck `.p8`**.
      - [ ] `cd ios && pod install` avant le build iOS ; tester App Attest sur **appareil réel**.

      **JOUR DE PUBLICATION (Play Store) :**
      - [ ] Keystore release + signing config (cf. TODO signing) → SHA-256 de l'upload key.
      - [ ] Play Console → activer **Play App Signing** → récupérer la **SHA-256 de la clé Google**
            → l'ajouter dans App Check (sinon Play Integrity rejette les installs Store).
      - [ ] Trafic « vérifié » majoritaire dans les métriques → enforcement en « Appliqué »
            **par produit** (Firestore, Storage, RTDB, Auth). Rappel : enforcement global par
            produit → Android ET iOS doivent être prêts avant d'enforcer.

### 🟡 Améliorations (post-MVP)
- [ ] **Photo de profil (avatar)** : champ `photoURL` présent dans le modèle, mais **aucune UI**
      pour choisir/uploader, et les règles Storage ne couvrent que `report_media/` (pas les avatars).
- [x] **Mode hors-ligne — Palier 1 ✅** : dégradation gracieuse + communication.
      - [x] `main.dart` : persistance Firestore **explicite** (`Settings`, cache illimité).
      - [x] `connectivity_plus` (^6.1.0, compat. toolchain) + `ConnectivityProvider` (`isOffline`).
      - [x] `app.dart` : **bandeau global « Hors ligne »** (`MaterialApp.builder` → `OfflineBanner`).
      - [x] ARB FR/EN : message du bandeau + message média offline.
      - [x] Form signalement : **garde média** hors ligne (l'upload Storage ne queue pas).
      - [x] Vérifié sur Samsung S916W (adb network off → bandeau OK + cache visible ; on → disparaît) ; `analyze` clean ; 70 tests.
      - Note : confirmer/restaurer (transactions) restent KO offline → contextualisés par le bandeau.
      - ⚠️ `connectivity_plus 7.x` exige compileSdk 36 + AGP 8.9.1 → resté en 6.x pour ne pas bumper le toolchain.
      - Palier 2 (différé) : confirmer/restaurer offline via `FieldValue.increment` (compromis anti-double-vote).
- [~] **Couverture de tests** (global ~25 % lignes côté Dart) :
      - [x] **P1 — Cloud Functions** ✅ : logique pure extraite (`functions/src/logic.ts`) +
            tests `node:test`/`tsx` (`logic.test.ts`, 10 cas : seuil d'auto-résolution,
            `shouldResolve`, `buildBody`). `npm test` dans `functions/`.
      - [x] **P2 — gains rapides Dart** ✅ : validators 100 %, `l10n_helpers` 100 %, `Report.fromDoc` 97 %,
            `connectivity_provider` 73 %, +branches `report_provider` (archive/markRestored) et
            `auth_provider` (changeEmail/changePassword). 95 tests, global 25 %→33 %.
      - [~] **P3 — services via `fake_cloud_firestore`** (pivot vs émulateur : CI-friendly, non-flaky,
            pas d'appareil) : `report_service` 0→76 % (transactions vote-unique, geohash, archive),
            `device_service` 0→93 % (upsert idempotent). 107 tests, global 33→37,5 %.
            Reste : `auth_service` (firebase_auth_mocks), `storage_service` (firebase_storage_mocks).
            `location_service`/`notification_service` = wrappers plugins natifs (GPS/FCM) → intégration
            sur appareil, peu de logique, ROI faible.
      - [ ] Widget tests des écrans clés (home/map/report_form) — ROI faible tant que pas publié.
- [ ] Vue opérateur/admin → **hors périmètre** (déportée vers un futur projet web séparé).

---

## 📌 À faire tout de suite (housekeeping)
- [ ] **Pousser** la branche : `master` est **ahead 1** (commit i18n `c22f253`) — pas encore sur `origin`.
- [ ] **Commiter `CLAUDE.md`** (actuellement non suivi).
