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
- [x] **Signing release Android** ✅ : keystore `android/app/njuka-release.jks` (CN=Bogal Consulting,
      valide jusqu'en 2053, alias `njuka`) + `android/key.properties` (gitignorés). `build.gradle.kts`
      câblé (signingConfig release, **repli debug** si key.properties absent → CI/autres machines OK).
      AAB release **signé vérifié** (`jarsigner` → CN=Bogal Consulting). Upload key SHA-256
      `48:F3:2F:23:…:67:0A`.
      ⚠️ **Mot de passe + `.jks` à sauvegarder hors machine** (perte = MAJ impossible sans Play App Signing).
      Build de publication : `flutter build appbundle --release --dart-define=STADIA_API_KEY=…`.
- [~] **Pages légales** :
      - [x] **Politique de confidentialité** bilingue FR/EN (`public/privacy.html`), fidèle aux données
            réelles (compte, géoloc, FCM, médias, Crashlytics, App Check) + hébergement **Firebase Hosting**
            (`firebase.json`) + lien in-app (Paramètres → Légal, via `url_launcher`).
      - [x] **Déployée** sur Firebase Hosting → live à `https://lightcutoff-dev.web.app/privacy` (HTTP 200).
      - [ ] **AVANT soumission store** : remplir les placeholders `[ÉDITEUR]` / `[date]` dans
            `public/privacy.html` + **relire par un juriste** (RGPD), puis re-déployer
            (`firebase deploy --only hosting` avec Node ≥20).
      - [ ] CGU / Mentions légales : différées (non strictement requises pour publier).
- [x] **Suppression de compte (RGPD / exigence stores)** : Cloud Function callable `deleteAccount`
      (anonymise les signalements ; supprime profil/pseudo/devices/médias/compte Auth) +
      UI `Profil → Paramètres → Compte → Supprimer mon compte` (ré-auth mot de passe) +
      page web `https://lightcutoff-dev.web.app/account-deletion` pour le Data Safety.
      Fonction + hosting **déployés**. analyze clean, 114 tests verts, functions 10/10.
      *Différé explicitement (« pas maintenant »).*

### 🟠 Important (qualité / robustesse)
- [ ] **🔒 Durcir la règle Firestore des compteurs (trou anti-faux)** *(vrai quick win, indépendant du nb d'users)*
      - **Problème** : `firestore.rules:67-72` protège l'écriture des compteurs via
        `affectedKeys().hasOnly([...])` — ça contrôle **quels champs** sont modifiés, **pas la
        valeur**. N'importe quel user connecté peut écrire `confirmationCount = 9999` en un
        `update`, **sans créer de document de vote**. La garantie « 1 vote/user » n'est PAS assurée
        par les règles, seulement par la bonne volonté du client.
      - **Fix (2 options)** : soit la règle impose
        `request.resource.data.confirmationCount == resource.data.confirmationCount + 1` **et**
        l'existence du doc de vote `confirmations/{uid}` ; soit **déporter l'incrément** vers une
        Cloud Function `onConfirmationCreated`/`onRestorationCreated` (l'Admin SDK contourne les
        règles, le client n'écrit plus le compteur). Idem `restorationCount`.
      - **Acceptation** : `rules_tests/` mis à jour prouvant qu'un écrit arbitraire du compteur est
        **refusé** · analyze/test verts.
- [ ] **📈 Analytics de funnel minimal** *(préalable à TOUTE feature d'engagement / mesure)*
      - **Pourquoi** : sans mesure, impossible de savoir si les features d'engagement (preuve
        sociale, prédiction, alertes) changent quoi que ce soit. On navigue à l'aveugle.
      - **Scope** : événements clés (signalement créé, confirmation, restauration, ouverture détail,
        ouverture app) via Firebase Analytics. Pas de PII. Tableau de bord funnel de base.
      - **Acceptation** : événements émis vérifiés en console · analyze/test verts.
- [x] **i18n des messages d'erreur providers/services** ✅ FAIT.
      Nouvel enum `AppError` (`lib/models/app_error.dart`) renvoyé par la couche data
      (`auth_provider`, `report_provider`, `location_service`/`LocationException`), traduit
      côté UI via `appErrorLabel(context, code)` (`l10n_helpers.dart`). 18 clés `errorXxx`
      ajoutées FR/EN. Tous les SnackBars d'erreur sont désormais localisés. 70 tests verts.
- [~] **Fournisseur de tuiles carte à clé** → **Stadia Maps** :
      - [x] Code branché : `TileLayer` Stadia (`alidade_smooth`) si `--dart-define=STADIA_API_KEY=…`,
            **repli OSM** sinon (dev/CI) ; **attribution** ajoutée (Stadia + OpenMapTiles + OSM, obligatoire).
            `AppConfig.stadiaApiKey` / `useStadiaTiles`. analyze clean, 114 tests OK.
      - [ ] **À FAIRE (toi)** : créer un compte Stadia Maps → générer une **clé API** → la **restreindre**
            (propriété mobile / plafond) dans le dashboard.
      - [ ] Builder avec la clé : `flutter run/build --dart-define=STADIA_API_KEY=xxxx`
            (et la passer en **secret CI** pour les builds release).
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

#### Preuve sociale & engagement (ex-plan T1-T4, réévalué)
> ⚠️ **Inutile à 0 user** : ces features amplifient un usage existant. À faire **après**
> distribution + analytics. Constat de l'audit : les compteurs `confirmationCount`/
> `restorationCount` **existent déjà** (modèle, increment transactionnel, UI, l10n) — donc
> l'ex-« T1 » se réduit aux deux items ci-dessous, pas à une fondation à construire.
- [ ] **Différenciation visuelle confirmé / non-confirmé** (ex-T1, reste réel) : un report à
      `confirmationCount == 0` reste discret/gris ; un report confirmé passe en **ambre** mis en
      avant. Aujourd'hui tout est en `AppColors.gray` (`report_card.dart`). Aligne poids visuel et
      fiabilité (un faux non confirmé ne doit pas être amplifié).
- [ ] **Fraîcheur visuelle de la carte** (ex-T3, la plus sûre) : style des marqueurs selon l'âge
      (< 10 min ambre vif/pulsation, < 1 h ambre, plus ancien estompé) ; pondérer la couleur des
      clusters par le membre le plus récent. 100 % client-side. ⚠️ vérifier la **perf** des
      animations avec le clustering sur gros volume.
- [ ] **Bandeau « activité de ta zone »** (ex-T2) : « ⚡ N coupures actives autour de toi ».
      ⚠️ **Faille de correction** : la liste est **paginée** (`reportsPageSize = 20`) → un comptage
      sur la liste chargée **sous-compte**. À résoudre avant : soit afficher un nombre plafonné
      (« 20+ »), soit un `count()` (qui coûte). Clarifier quelle source (liste temps réel vs requête
      proximité one-shot) alimente le bandeau.
- [ ] **Réduction de friction (multiplicateur de contribution)** : signalement **en 1 tap**,
      depuis la **notification**, depuis un **widget**. Souvent meilleur ROI que toute récompense.
- [ ] **Réputation pondérée par la justesse** (Tier 3, double comme anti-faux) : un signaleur dont
      les reports sont confirmés gagne en fiabilité ; les faux la perdent. Affiché sur le report
      (« signalé par une Vigie fiable »). **Motive ET renforce l'anti-faux** avec un seul mécanisme.
      → motivation alignée sur la **qualité**, pas le volume (éviter gamification/récompenses
      matérielles qui incitent au spam).

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
      - [x] **P3 — services via fakes** (pivot vs émulateur : CI-friendly, non-flaky, pas d'appareil) :
            `report_service` 0→76 % (transactions vote-unique, geohash, archive),
            `device_service` 0→93 % (upsert idempotent),
            `auth_service` 0→49,5 % (pseudo→email, compte désactivé, register) via
            `fake_cloud_firestore` + `firebase_auth_mocks`. 114 tests, global 25→41,6 %.
            Restent à 0 % (volontaire) : `location_service`/`notification_service` (wrappers plugins
            natifs GPS/FCM, peu de logique) ; `storage_service` (thin wrapper). auth_service :
            changeEmail/Password non couverts (exigent des mocks de ré-authentification).
      - [ ] Widget tests des écrans clés (home/map/report_form) — ROI faible tant que pas publié.
- [ ] Vue opérateur/admin → **hors périmètre** (déportée vers un futur projet web séparé).
- [ ] **Fil de coupure (discussion locale éphémère)** → **VISION V2 cadrée** dans
      `docs/VISION-fil-coupure.md`. Discussion attachée à un signalement, ne vit que le temps de
      la coupure. Gating par confirmation, modération obligatoire (stores), livraison par paliers
      (timeline → réactions → texte → photos). **À coder seulement après distribution + vrais users.**
- [ ] **⭐ Horaire de délestage (réciprocité utilité)** → **VISION cadrée** dans
      `docs/VISION-horaire-delestage.md`. **Proposition de valeur centrale** : prédire quand le
      courant part/revient par zone (geohash) à partir de la donnée collective ; alertes proactives
      ; affinage gated par contribution. Contexte Eneo Cameroun (officiel = travaux planifiés ;
      NJUKA = délestage quotidien réel). Cold-start favorable (événements quotidiens). Paliers :
      historique → horaire+confiance → alerte push → patterns/gated → amorçage Eneo. Préalable :
      distribution + analytics.

---

### ⭐ Épic « Valeur donnée » — délestage (réf. `docs/VISION-horaire-delestage.md`)

> **Préalable transverse** : distribution débloquée (test interne) + **analytics de funnel** en
> place. Ne rien coder avant d'avoir de vrais utilisateurs et de quoi mesurer l'impact.

- [ ] **1. Statistiques utilisateur sur ses données de coupures** *(palier 0 — faible risque)*
  - **Pourquoi** : rendre à l'utilisateur une info perso à forte valeur (réciprocité) — il revient
    pour **sa** donnée. Aucune prédiction → aucune fausse promesse, utile même à faible volume.
  - **Scope** : tableau de bord **« mes signalements »** + **« ma zone »** (cellule geohash) bâti
    sur les reports existants (horodatés + geohash) : nombre de coupures, durée cumulée/moyenne,
    répartition par heure et par jour, tendance sur la période (semaine/mois). **Agrégats
    uniquement** (RGPD, aucun suivi individuel).
  - **Acceptation** : `flutter analyze` clean · `flutter test` vert · rendu correct sur jeu de
    données **faible/vide** (pas de division par zéro, état vide explicite).

- [ ] **2. Ingestion du programme de coupures Eneo (amorçage)** — ✅ **source confirmée**
  - **Pourquoi** : amorcer avec les coupures **planifiées officielles** → valeur dès le 1ᵉʳ user +
    parité avec l'alerte « par quartier » d'Eneo.
  - **Endpoint** (vérifié live) : `POST https://alert.eneo.cm/ajaxOutage.php` avec `region=<1-10>`
    (10 régions CM, ordre alpha ; nom dans la réponse). Réponse `{"status":1,"data":[{observations,
    prog_date, prog_heure_debut, prog_heure_fin, region, ville, quartier}]}`. Heures locales
    Africa/Douala (UTC+1). Détails complets : `docs/VISION-horaire-delestage.md` §5.2.
  - **Scope** : Cloud Function cron quotidienne → itère region 1-10 → normalise vers le schéma
    canonique `official_outages/` → upsert dédupliqué (`rawHash`). **Nettoyage obligatoire** :
    trim quartier, drop quartiers vides, dédup doublons.
  - **Architecture multi-pays** : `EneoAdapter` derrière une interface `OutageSourceAdapter`
    (`fetch`/`normalize`) → ajouter un pays = un nouvel adaptateur.
  - **Risques** : endpoint **non officiel/non documenté** (peut changer) → échouer proprement,
    bonus jamais dépendance. **CGU Eneo à vérifier.** ⚠️ contenu = **travaux planifiés**, PAS le
    délestage quotidien (couche distincte du crowd).
  - **Acceptation** : `normalize` = **fonction pure testée** sur le vrai schéma observé · cron
    idempotent · données nettoyées (pas de doublon/vide) en base.

- [ ] **3. Système de prédiction d'horaire de délestage** *(cœur de valeur)*
  - **Pourquoi** : répondre à « **quand le courant part/revient chez moi ?** » — la raison
    d'ouvrir NJUKA tous les jours.
  - **Scope** : par cellule geohash, agréger les événements **off** (création report) / **on**
    (résolution) → prédiction **statistique simple** (heure typique off/on : mode/médiane) +
    **indicateur de confiance** (= nb d'observations distinctes). Palier suivant : **patterns par
    jour de semaine** (délestage rotatif). **Granularité geohash adaptative** selon la densité.
    Stockage : calcul à la volée **ou** collection dérivée `schedules/{geohash}` — à trancher selon
    le volume. (Les **alertes proactives** push se greffent par-dessus — tâche séparée.)
  - **Garde-fou** : 🔴 **afficher la confiance honnêtement** — jamais une devinette présentée comme
    certitude. Une prédiction fausse détruit la confiance plus vite qu'une bonne ne la construit.
  - **Acceptation** : **logique de prédiction isolée en fonction pure + testée** (comme
    `functions/src/logic.ts`) · comportement correct sous **faible densité** · pas de prédiction
    affichée sous le seuil minimal d'observations.

- [ ] **4. Alerte proactive de délestage (push)** *(le crochet émotionnel)*
  - **Pourquoi** : prévenir **avant** la coupure/le retour prédits (« coupure probable dans 30 min
    — charge tes appareils ») = l'info qui change la vie en délestage quotidien. Le push porte un
    **confirm 1-tap** → nourrit la donnée de prédiction. Double bénéfice : valeur + collecte.
  - **Scope** : Cloud Function qui, à partir des prédictions (tâche 3), cible par cellule geohash
    les `devices` concernés ; notification avec action « Confirme l'état ». **Anti-fatigue** : cap
    quotidien, fenêtre horaire raisonnable, 1 push pertinent / device / fenêtre. Se greffe sur la
    prédiction.
  - **Dépend de** : tâche 3 (prédiction). ⚠️ **Android-only** au début (push iOS gelé).
  - **Acceptation** : `npm test` (functions) vert avec logique de ciblage testée · throttling
    effectif · pas de double notification.

---

## 📌 À faire tout de suite (housekeeping)
- [ ] **Pousser** la branche : `master` est **ahead 1** (commit i18n `c22f253`) — pas encore sur `origin`.
- [ ] **Commiter `CLAUDE.md`** (actuellement non suivi).

---

## 🛠️ PLAN — Phase 2a : Liste/recherche des coupures planifiées (UI)

> 🔄 **REDESIGN (Option 1, choisi)** : l'écran séparé + l'icône AppBar sont **remplacés** par un
> **sélecteur segmenté** dans la Liste — `Toutes / Signalements / Programmées`. « Toutes » =
> sections « En cours » (signalements) + « À venir · Eneo » (planifiées). `OfficialOutagesScreen`
> supprimé ; vue réutilisable `lib/widgets/official_outages_view.dart` ; `home_screen.dart` réécrit
> (Stateful + `_SegmentedControl`, provider planifié créé en lazy). 4 clés i18n `homeSegment*`.
> **Démontré live sur émulateur** (3 segments OK, vraies données Eneo). analyze clean · 119 tests.
>
> ✅ **FAIT & VÉRIFIÉ (2026-06-10)** : `flutter analyze` clean · **119 tests verts** (5 nouveaux :
> modèle `fromDoc`, service `fetchUpcoming` via fake Firestore, provider filtre/régions).
> Fichiers : `lib/models/official_outage.dart`, `lib/repositories/official_outage_repository.dart`,
> `lib/services/official_outage_service.dart`, `lib/providers/official_outage_provider.dart`,
> `lib/widgets/official_outage_card.dart`, `lib/screens/official_outages_screen.dart`,
> `AppColors.planned`, `NjukaAppBar.extraActions` + entrée AppBar accueil (icône `event_note`),
> i18n FR/EN (6 clés `officialOutages*`). Backend : `startTime`/`endTime` ajoutés (18 tests functions).
> ⚠️ **Démo** : `official_outages` est **vide en prod** (l'ingestion n'a tourné que sur l'émulateur)
> → pour voir l'écran peuplé, lancer l'app en `--dart-define=USE_EMULATOR=true` + seed émulateur.

> Affiche `official_outages` aux utilisateurs : écran **browsable** region→ville→quartier +
> recherche, **lecture seule**, **sans géocodage ni matching** (socle pour 2b « suivre mon
> quartier »). Couche **distincte** (bleu « planifié ») des signalements communautaires (ambre).

### 2a-0 — Petit ajout backend (affichage fiable des heures)
- [ ] Stocker `startTime`/`endTime` (HH:MM locales) dans `official_outages` (en plus des
      Timestamps UTC) → évite la conversion de fuseau côté UI. MAJ `CanonicalOutage`,
      `normalizeEneo` (+ test), et l'écriture dans `runEneoIngestion`.

### 2a — Flutter (couches : modèle → repo → service → provider → écran)
- [ ] **Modèle** `lib/models/official_outage.dart` : `fromDoc` (region, ville, quartier, reason,
      progDate, startTime, endTime, startsAt, endsAt) — pattern `Report.fromDoc`.
- [ ] **Repo** `lib/repositories/official_outage_repository.dart` :
      `Future<List<OfficialOutage>> fetchUpcoming()`.
- [ ] **Service** `lib/services/official_outage_service.dart implements …` : requête
      `collection('official_outages').where('progDate', >=, today).orderBy('progDate').get()`
      (champ unique → pas d'index composite), map `fromDoc`.
- [ ] **Provider** `lib/providers/official_outage_provider.dart` (ChangeNotifier) : charge à
      l'init, état loading/error/data, **filtre région** + **recherche quartier**, getter groupé.
      Créé **à l'ouverture de l'écran** (lazy), pas dans le MultiProvider global.
- [ ] **Widget** `lib/widgets/official_outage_card.dart` : style **bleu « Travaux planifiés »**
      (ajouter `AppColors.planned`), quartier (titre), ville·région, **date + créneau
      `06:00–18:00`**, motif. Distinct des `ReportCard` (ambre).
- [ ] **Écran** `lib/screens/official_outages_screen.dart` : AppBar + champ recherche + filtre
      région (chips/dropdown) + liste groupée + états vide/chargement/erreur.
- [ ] **Point d'entrée** : action AppBar (icône calendrier) sur `HomeScreen` → push de l'écran
      avec `ChangeNotifierProvider(create: (_) => OfficialOutageProvider())`.
- [ ] **i18n** : ~10 clés FR/EN (titre, recherche, filtre région, « le {date} », créneau, motif,
      état vide, libellé « Travaux planifiés · Eneo ») + `flutter gen-l10n`.

**Acceptation** : `flutter analyze` clean · `flutter test` vert (test modèle `fromDoc` + provider
via `fake_cloud_firestore`) · liste groupée rendue, recherche fonctionnelle, état vide géré.

**Hors 2a (→ 2b)** : « suivre mon quartier » (choix sauvegardé au profil) + alerte push avant le
créneau ; endpoint Eneo listant **tous** les quartiers (picklist complète) ; carte (2c).

---

## 🛠️ PLAN ACTIF — Ingestion Eneo (V1 backend only)

> ✅ **V1 BACKEND LIVRÉ & VÉRIFIÉ (2026-06-10).** Étapes 1-4 faites. Vérifs :
> `tsc` clean · `npm test` **17/17** (7 nouveaux `normalizeEneo`) · **rules tests 27/27**
> (lecture OK + écriture client refusée sur `official_outages`) · **intégration live**
> fetch+normalize = **660 bruts → 652 uniques**, 5 régions, horaires UTC corrects, 0 vide.
> Fichiers : `functions/src/sources/{types,eneo}.ts`, `functions/src/eneo.test.ts`,
> `functions/src/index.ts` (`ingestEneoOutages` cron + `runEneoIngestion` exporté),
> `functions/scripts/seedEneo.cjs`, `firestore.rules` + `rules_tests/`.
> ✅ **Smoke test écriture émulateur VALIDÉ** (2026-06-10) : 652 docs écrits, **idempotent**
> (2ᵉ run = 652), 0 quartier vide, horaires UTC OK. Via `seedEneo.cjs` (cf. `TESTS-MANUELS.md`).
> ⚠️ **Pas de déclencheur HTTP** : le worker HTTPS de l'émulateur firebase-tools plante avec
> firebase-functions v7 (bug outillage, pas le code ; cron de prod non concerné) → on lance
> l'ingestion en appel direct via le script.
> **Reste** : (a) phase 2 (géocodage + UI) ; (b) vérifier CGU Eneo avant prod.

> Étape 2 de l'épic délestage. **100 % backend (Cloud Functions)** → constructible et testable
> **indépendamment de la distribution**. UI app + carte = phase 2 séparée (hors de ce plan).
> Réf. design : `docs/VISION-horaire-delestage.md` §5.2.
>
> Endpoint (vérifié live) : `POST https://alert.eneo.cm/ajaxOutage.php` body `region=<1-10>` →
> `{"status":1,"data":[{observations, prog_date, prog_heure_debut, prog_heure_fin, region, ville,
> quartier}]}`. Heures locales **Africa/Douala (UTC+1, pas de DST)**.

### Étape 1 — Schéma + règles Firestore
- [ ] Collection **`official_outages/{rawHash}`** (id = hash stable → upsert idempotent) :
      `provider:"eneo"`, `country:"CM"`, `region`, `ville`, `quartier`, `reason`, `progDate`,
      `startsAt` (Timestamp UTC), `endsAt`, `geo?` (phase 2), `sourceUrl`, `fetchedAt`.
- [ ] `firestore.rules` : **lecture** = `isSignedIn()` ; **écriture client = refusée**
      (alimentée uniquement par l'Admin SDK, qui contourne les règles).
- [ ] `rules_tests/` : prouver qu'un write client sur `official_outages` est **refusé**.

### Étape 2 — Architecture adaptateur (multi-pays) dans `functions/src/sources/`
- [ ] `sources/types.ts` : interface `OutageSourceAdapter { fetch(): Promise<Raw[]>;
      normalize(raw): CanonicalOutage[] }` + type `CanonicalOutage`.
- [ ] `sources/eneo.ts` : `EneoAdapter`.
      - `fetchRegion(code)` : `fetch()` global (Node 22), POST form `region=code`, parse `.data`.
      - **`normalizeEneo(rawItems)` = fonction PURE** (aucun I/O) : trim tous les champs, **drop
        quartier vide**, `startsAt/endsAt` via `new Date(\`${progDate}T${heure}:00+01:00\`)`,
        `rawHash` = SHA-1 de `eneo|region|ville|quartier|progDate|debut|fin`, **dédup intra-lot**.

### Étape 3 — Logique pure + tests (modèle `logic.ts` / `logic.test.ts`)
- [ ] `sources/eneo.test.ts` (`tsx --test`) sur un **fixture du vrai schéma observé** :
      trim espaces parasites (« ` QUARTIER GENTIL` »), drop vides, dédup doublons (NDOGBONG ×2),
      conversion horaire UTC+1 correcte, stabilité du `rawHash`.

### Étape 4 — Cloud Function cron
- [ ] `export const ingestEneoOutages = onSchedule({schedule:"every 24 hours",
      timeZone:"Africa/Douala", retryCount:0}, …)` (même pattern que `purgeArchivedReports`).
      - Itère `region` 1→10 ; **try/catch par région** (échoue proprement, ne jette jamais tout
        le job — donnée = bonus, pas dépendance) ; log par région.
      - `normalize` → **upsert** `official_outages/{rawHash}` (merge) avec `fetchedAt`.
      - **Prune** les entrées dont `progDate < aujourd'hui`.
- [ ] (optionnel) variante **HTTP/callable** `ingestEneoOutagesNow` pour déclencher à la main en
      émulateur (test sans attendre le cron).

### Étape 5 — Vérification
- [ ] `cd functions && npm test` **vert** (normalize testé sur le vrai schéma).
- [ ] `npm run build` (tsc) **clean**.
- [ ] **Émulateur** : déclencher l'ingestion → vérifier docs créés, **dédupliqués**, horaires UTC
      corrects, quartiers vides absents.

### Hors V1 (phase 2, plan séparé)
- [ ] Géocodage `ville+quartier` → `geo {lat,lng,geohash}` (Nominatim, mis en cache).
- [ ] UI app : liste/recherche région→ville→quartier (« Travaux planifiés Eneo », couche distincte).
- [ ] Surbrillance carte (zones approximatives, style distinct des pins communautaires).

### ⚠️ Avant mise en prod
- [ ] **Vérifier les CGU Eneo** (extraction automatisée autorisée ?).
- [ ] Edge non couvert V1 : travaux **annulés** par Eneo (entrée future qui disparaît du flux) —
      stratégie de prune à décider (sortir du périmètre V1).
