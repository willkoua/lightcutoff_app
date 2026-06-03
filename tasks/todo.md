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
- [~] **Firebase App Check** — client intégré ✅ (`firebase_app_check`, `activate()` dans
      `main.dart` : Play Integrity / AppAttest+DeviceCheck / debug provider en dev).
      **Reste MANUEL (console/natif)** :
      1. ⚠️ **Repasser l'enforcement OFF** le temps que la nouvelle version soit adoptée
         (sinon les utilisateurs des anciens builds sont bloqués).
      2. Enregistrer le **debug token** (imprimé dans les logs au 1er run debug) :
         Firebase → App Check → app → « Gérer les jetons de debug ».
      3. Uploader la **clé privée DeviceCheck (.p8)** en console (repli iOS < 14).
      4. Lier l'app à **Play Integrity** (Play Console / SHA-256) pour le release Android.
      5. `cd ios && pod install` avant le prochain build iOS.
      6. Réactiver l'enforcement **par produit** une fois le trafic « vérifié » visible
         dans les métriques.

### 🟡 Améliorations (post-MVP)
- [ ] **Photo de profil (avatar)** : champ `photoURL` présent dans le modèle, mais **aucune UI**
      pour choisir/uploader, et les règles Storage ne couvrent que `report_media/` (pas les avatars).
- [ ] **Mode hors-ligne assumé** : activer la persistance Firestore offline + indicateur de connexion.
- [ ] **Couverture de tests** : services Firebase peu couverts ; pas de widget tests des écrans clés
      (home, map, report_form) ni de tests d'intégration sur émulateur.
- [ ] Vue opérateur/admin → **hors périmètre** (déportée vers un futur projet web séparé).

---

## 📌 À faire tout de suite (housekeeping)
- [ ] **Pousser** la branche : `master` est **ahead 1** (commit i18n `c22f253`) — pas encore sur `origin`.
- [ ] **Commiter `CLAUDE.md`** (actuellement non suivi).
