# NJUKA — État du programme (plan détaillé fait / non fait)

> Audit basé sur le **code réel** (pas sur CONTEXT.md, qui date du 22 mai et est en
> retard sur les faits). Vérifié le 2026-06-03. `flutter analyze` clean, **70 tests verts**.

> 🚀 **2026-06-13 — `1.1.0+4` déployé en TEST INTERNE Play Store** (env staging `lightcutoff-dev`).
> Inclut tous les correctifs récents (crash minify, carte centrée/affichée, popups de validation,
> indicateur « déjà voté », onglets stats, profil sans rôle, proximité par défaut, sécurité
> compteurs durcie, analytics). Prochain jalon : **retours testeurs + 1ères données analytics**.

---

## 🛠️ PLAN ACTIF — Étape 3 : Service Eau (multi-service)

> Phase suivante du pivot 2026-06-24, à attaquer une fois l'étape 1 validée
> sur appareil. Pourquoi : double l'utilité de l'app (CAMWATER aussi commun
> qu'Eneo au Cameroun) sans refaire l'UX — même moteur de signalement,
> votes, géohash, auto-résolution.

### Invariants à préserver
- **Le moteur métier ne bouge pas** : géoloc, votes (`confirmations` /
  `restorations`), auto-résolution Cloud Function, géohash → tous
  agnostiques au service. On ne refactore PAS ce qui marche.
- **Backward compat** : tous les reports existants sont **électricité**
  (le seul service qui existait). Le champ `serviceType` est ajouté avec
  défaut `electricity` côté lecture (`Report.fromDoc`) pour ne pas casser
  l'historique.
- **Ingestion Eneo intacte** : la Cloud Function `ingestEneoOutages`
  continue de tagger `serviceType = electricity` sur les `official_outages`.
  Pas d'ingestion eau pour v1 (CAMWATER n'a pas d'API publique connue).
- **Notifications, follow quartier, App Check** : zéro impact.

### Décisions verrouillées (2026-06-24)
1. **Modèle fournisseurs** = **unifié** : `Utility { id, service, country,
   label }` → 1 seule liste mixte `kSupportedUtilities`. Élimine la
   duplication, scale propre quand on ajoutera Senelec/JIRAMA/etc.
2. **Persistance filtre service** = mémorisation du **dernier choix**
   dans SharedPreferences. Démarrage par défaut : `null` (Tout). Le user
   peut fixer Élec / Eau et son choix est rejoué au prochain lancement.
3. **Couleur eau** = `#0EA5E9` (sky-500). `AppColors.water` (ongoing) +
   réutilisation `AppColors.resolved` (vert existant) pour le rétabli.
4. **Causes** = **statu quo**, pas d'enum `OutageCause`. La `description`
   libre couvre les deux services. Pas de friction supplémentaire au
   formulaire.

### Architecture cible

```
ServiceType { electricity, water }
   ↓ porté par chaque Report
Report (existant) {
   serviceType   ← NOUVEAU, default electricity
   userId, status, position, location, type,
   confirmations, restorations, ...
}

Utility (ou WaterProvider/ElectricityProvider)
   ↓ rattaché à un pays + un service
   CM → Eneo (electricity)
   CM → CAMWATER (water)

RegionProvider {
   activeCountry           ← inchangé (override → GPS → home → locale → CM)
   activeProvider(service) ← NOUVEAU getter paramétré par ServiceType
   activeServiceFilter     ← NOUVEAU : null | ServiceType (persisté)
}

ReportProvider {
   setServiceFilter(ServiceType?)  ← NOUVEAU
   watchReports(...)               ← injecte le where('serviceType', ==) si filtre
}

UI :
   ReportFormScreen   → sélecteur radio Électricité / Eau (default elec)
   HomeScreen / list  → segmented control en haut
   MapScreen          → segmented control + marqueurs différenciés
                        (couleur + icône lightning/water_drop)
   ReportCard         → petit chip de service en tête
   StatsScreen        → split par service (mes coupures elec / eau)
```

### Phases (à dérouler dans l'ordre)

#### Phase A — Fondation modèle ✅ (2026-06-24)
- [x] `ServiceType { electricity, water }` (lib/models/enums.dart) + `fromName`
      avec défaut `electricity` (rétro-compat).
- [x] `Report.serviceType` champ + `fromDoc` (parse) + `toCreateMap`
      (sérialise). Constructeur défaut `electricity`.
- [x] `OfficialOutage.serviceType` (constant `electricity` pour Eneo).
- [x] Helper i18n `serviceTypeLabel(context, ServiceType)` + 2 clés FR/EN.
- [x] 4 tests modèle (parsing, défaut legacy, round-trip eau).
- [x] **Aucune modif Firestore rules** — défaut `electricity` à la lecture
      garantit la rétro-compat, aucun backfill nécessaire.

#### Phase B — Région & fournisseurs multi-service ✅ (2026-06-24)
- [x] Renommage `electricity_providers.dart` → [utilities.dart]
      (`Utility { id, service, country, label, … }` unifié, décision 1B).
- [x] Liste `kSupportedUtilities` = **Eneo (CM, elec) + CAMWATER (CM, eau)**.
- [x] Helpers `utilitiesForCountry`, `utilityForCountryAndService`.
- [x] `RegionProvider` :
      - `activeUtility(ServiceType)` getter paramétré.
      - `activeProvider` conservé comme **alias** electricity (rétro-compat).
      - `serviceFilter` (`ServiceType?`) + `setServiceFilter` + persistance
        SharedPreferences clé `service_filter` (décision 2B).
      - Override sémantique : ne s'applique qu'au service correspondant
        (poser CAMWATER en override n'affecte PAS la résolution électrique).
- [x] `settings_screen.dart` picker : liste mixte (Eneo + CAMWATER), commentaire
      mis à jour.
- [x] 3 tests RegionProvider (activeUtility paramétré, override CAMWATER ciblé,
      persistance serviceFilter).

#### Phase C — Création & affichage ✅ (2026-06-24)
- [x] `AppColors.water = #0EA5E9` (sky-500, décision 3).
- [x] Helpers `serviceTypeIcon` (bolt / water_drop) + `serviceTypeColor`
      (lib/widgets/service_visuals.dart).
- [x] `ReportProvider.submitReport` + `createFromDraft` acceptent
      `serviceType` (default `electricity`).
- [x] `ReportFormScreen` : `SegmentedButton<ServiceType>` en tête,
      `_serviceType` initialisé depuis `region.serviceFilter` (sinon elec).
- [x] `ReportCard` : nouveau `_ServiceChip` (icône + libellé colorés) à côté
      du `_StatusChip`. Banalisation auteur anonyme préservée.
- [x] `MapScreen` : marqueurs via `_ServiceMarker` (pin coloré statut/service +
      mini icône service centrée en cocarde blanche).
- [x] Sémantique couleur : résolu = vert commun ; en cours = couleur service.
- [x] 2 tests widget `ReportCard` (chip Électricité / chip Eau).

#### Phase D — Filtre liste/carte ✅ (2026-06-24)
- [x] `ReportProvider._serviceFilter` + `setServiceFilter` + filtrage
      **client-side** dans `filteredReports` (volume MVP OK, pas d'index
      Firestore à créer — décision plan).
- [x] `_serviceFilter` exclu de `hasActiveFilters` (vue persistée, segmented
      control toujours visible — pas un filtre transitoire).
- [x] `AuthGate` proxy propage `region.serviceFilter` → `ReportProvider`.
- [x] [service_filter_bar.dart] : SegmentedButton<ServiceType?> à 3 segments
      (Tout / Élec / Eau) lisant + écrivant `RegionProvider.serviceFilter`.
- [x] HomeScreen : ServiceFilterBar visible uniquement sur l'onglet « Liste »
      (les coupures planifiées Eneo sont électricité par construction).
- [x] MapScreen : overlay Material blanc + élévation 2 sous l'AppBar,
      empilé sous la bannière « filtres actifs ».
- [x] 1 clé i18n `serviceFilterAll`.
- [x] 3 tests ReportProvider (null = tout / water = filtre / pas dans
      `hasActiveFilters`).

#### Phase E — Stats split + smoke tests ✅ (2026-06-24)
- [x] `StatsProvider` : refactor pour conserver les **listes brutes**
      (`_mineReports`, `_zoneReports`) ; calcul des `OutageStats` à la volée
      via `mineFor(ServiceType?)` / `zoneFor(ServiceType?)`. Pas de
      rechargement réseau au changement de filtre.
- [x] `StatsScreen` : `ServiceFilterBar` en tête (cohérent avec liste/carte) ;
      `mineFor`/`zoneFor` appelés avec `region.serviceFilter` → recalcul
      instantané.
- [x] 3 tests StatsProvider (mine tous services / mineFor filtré / pas de
      rechargement réseau / loading state).
- [x] **`tasks/TESTS-MANUELS.md`** : section « Multi-service Eau » avec 7
      scénarios bout-en-bout (sélecteur formulaire → filtre liste/carte →
      marqueurs → anti-doublon par service → auto-résolution croisée →
      stats split → sélecteur dev mixte) + régression rétro-compat + pièges
      (pas d'index, ingestion Eneo non touchée).

### Récap i18n étape 3 (4 clés ajoutées)
- `serviceElectricity` / `serviceWater` (libellés enum).
- `serviceFilterAll` (segment « Tout »).
- `reportFormServiceLabel` (libellé sélecteur formulaire).

### Bilan final étape 3
- `flutter analyze` clean · `dart format` clean · **180/180 tests Flutter**
  (+11 nouveaux : 4 modèle + 3 region + 2 ReportCard + 3 ReportProvider + 3
  StatsProvider — les Phase C/D/E sont couvertes).
- Backward compat : reports legacy lus comme `electricity` (default
  `ServiceType.fromName`), aucun backfill nécessaire.
- Pas d'index Firestore créé (filtrage client-side).
- Ingestion Eneo : tague toujours `electricity` (CanonicalOutage.serviceType
  par défaut côté modèle TS). Adaptateur CAMWATER = hors scope étape 3.
- À faire avant publication : smoke test bout-en-bout sur appareil
  (cf. `tasks/TESTS-MANUELS.md` § « Multi-service Eau »).

### Risques connus
- **Index Firestore manquant** : la première requête filtrée lèvera une
  exception « index required » côté client. Identifier les index nécessaires
  AVANT déploiement (les créer via Firebase console ou commit dans
  `firestore.indexes.json` qu'il faudra peut-être créer).
- **Migration des reports existants** : aucun ne porte `serviceType`. Le
  défaut `electricity` à la lecture (`fromDoc`) le rend invisible : aucun
  backfill nécessaire pour v1. Documenter dans `SCHEMA.md`.
- **Brand NJUKA** : nom évoque l'électricité. Pour v1 on garde — si
  l'usage eau prend de l'ampleur, repenser le slogan.
- **Ingestion Eneo** : continue de tagger `serviceType = electricity` à
  l'écriture — à patcher côté Cloud Function (`functions/src/sources/eneo.ts`).

---

## 🚦 PIVOT STRATÉGIQUE — décidé 2026-06-24

Décision produit en 3 étapes, attaquées dans l'ordre :

1. **Auth anonyme par défaut** (étape 1, planifiée ci-dessous) — supprimer la friction du
   login obligatoire. Lecture + signalement + vote possibles sans compte, via Firebase
   Anonymous Auth (uid présent → règles Firestore inchangées, intégrité du vote préservée).
   Les fonctions sociales (profil, notifs, suivi quartier, stats) deviennent des **murs
   d'upgrade**. `linkWithCredential` préserve l'uid lors de l'upgrade → l'historique anonyme
   reste attaché.
2. **Lecture publique sans aucune auth** (étape 2, optionnelle, à trancher après mesure) —
   pour partage web / lien direct sur carte. Pas planifiée ici.
3. **Service Eau** (étape 3, gros chantier, planifié séparément) — introduire `ServiceType
   { electricity, water }` au-dessus de `OutageType`, refactor `RegionProvider`, filtres carte/
   liste, couleurs distinctes. **À FAIRE APRÈS étape 1**, pour ne pas mélanger deux refactors.

---

## 🛠️ PLAN ACTIF — Étape 1 : Migration auth anonyme

> Pourquoi : conversion (zéro mur à l'entrée) + friction zéro au 1ʳᵉ signalement, sans casser
> l'intégrité du vote ni les règles Firestore existantes.

### Invariants à préserver
- **Règles Firestore actuelles fonctionnent telles quelles** : `isSignedIn()` est vrai pour un
  anonyme (uid présent). `castsVote` + `bumpsCounterByOne` restent valides → 1 vote / uid /
  report inchangé. Pas de modif de rules attendue (audit + tests à ajouter quand même).
- **App Check reste actif** (debug provider en dev, Play Integrity en release). Seule vraie
  défense anti-spam côté anonyme.
- **`authorUsername` denormalisé** = `null` en anonyme. UI affiche « Anonyme » via i18n.
- **Reinstall = nouvel uid anonyme**. On l'accepte pour v1. Mitigations différées : rate limit
  Cloud Function par App Check token + plafond reports/uid/jour.
- **Upgrade conserve l'uid** : `linkWithCredential` → tous les reports/votes anonymes restent
  attachés à l'utilisateur après création du compte.

### Architecture cible

```
OnboardingGate
 └─ AuthGate (6 états, +1 : anonymous)
     ├─ unknown              → SplashScreen
     ├─ anonymous            → MainShell  ← NOUVEAU, route par défaut
     ├─ authenticated        → MainShell (avec profil) — inchangé
     ├─ awaitingVerification → EmailVerificationScreen (post-upgrade only)
     ├─ profileIncomplete    → CompleteProfileScreen (post-social only)
     └─ unauthenticated      → écran « Réessayer » (signInAnonymously a échoué)
                                 LoginScreen reste accessible depuis Profile
```

`LoginScreen` / `RegisterScreen` ne sont plus la racine : ce sont des destinations
accessibles depuis le **mur d'upgrade** du Profil.

### Tâches (ordre d'attaque)

#### 1. Console Firebase + audit règles
- [ ] **À FAIRE par toi (manuel)** : Console `lightcutoff-dev` → Authentication → Sign-in
      method → **activer Anonymous**. Sans ça, `signInAnonymously()` échoue avec
      `admin-restricted-operation`.
- [x] **Helper `isAnonymous()`** ajouté à `firestore.rules` (basé sur
      `request.auth.token.firebase.sign_in_provider == 'anonymous'`).
- [x] **Verrouillage côté rules** : interdire en session anonyme la création/MAJ de
      `users/{uid}`, `usernames/{username}`, `devices/{token}` → force le passage par
      l'upgrade pour ces ressources sociales. (Inutile sur `reports/` et sous-collections
      `confirmations`/`restorations` — qui doivent rester ouvertes aux anonymes.)
- [x] **Tests rules ajoutés** (`rules_tests/test/firestore.spec.js`, helper `asAnonymous`
      avec `sign_in_provider: "anonymous"`) — 6 cas :
      1. Un anonyme crée un report avec son propre uid (et ne peut pas mentir sur l'auteur).
      2. Un anonyme vote (confirm + restore atomique) sur le report d'un autre.
      3. Un anonyme ne peut PAS créer `users/{son_uid}` (ni `users/{autre_uid}`).
      4. Un anonyme ne peut PAS réserver `usernames/{x}`.
      5. Un anonyme ne peut PAS enregistrer `devices/{token}`.
      6. Régression upgrade : après linkWithCredential (sign_in_provider ≠ anonymous),
         la création de profil + pseudo redevient OK.
- [x] **37/37 tests rules verts** (6 nouveaux + 31 existants intacts) via
      `npm --prefix rules_tests run test:emulator`.
- [ ] **À déployer** quand tu actives Anonymous Auth : `firebase deploy --only firestore:rules`
      (pour pousser les nouvelles règles `!isAnonymous()` sur lightcutoff-dev).
- [ ] App Check : vérifier que les sessions anonymes passent (debug token déjà enregistré)
      — à confirmer en runtime lors de la tâche 3.

#### 2. AuthRepository / AuthService — nouvelles méthodes ✅ (2026-06-24)
- [x] `AuthRepository` (interface) :
      - `bool get isAnonymous` (symétrique à `isEmailVerified`).
      - `Future<void> signInAnonymously()`.
      - `Future<void> upgradeAnonymous({email, password, firstName, lastName, username,
        phoneNumber?, birthDate?})` — link + creation atomique + vérification email.
- [x] `AuthService` (impl Firebase) :
      - `signInAnonymously` = `_auth.signInAnonymously()`.
      - `upgradeAnonymous` :
        1. Refuse si `currentUser` n'est pas anonyme (`code: 'no-current-user'`).
        2. Pré-check `isUsernameAvailable` → `username-already-in-use` si pris.
        3. `user.linkWithCredential(EmailAuthProvider.credential(email, password))` →
           uid PRÉSERVÉ, sign_in_provider passe à « password ».
        4. **`getIdToken(true)`** force le rafraîchissement du token avant le batch
           Firestore (sinon risque PERMISSION_DENIED car le token cache encore
           sign_in_provider = anonymous → les nouvelles règles `!isAnonymous()`
           bloqueraient la création de profil).
        5. `updateDisplayName` + batch atomique (`users/{uid}` + `usernames/{u}`).
        6. `sendEmailVerification` → bascule auto en `awaitingVerification`.
- [x] Erreurs Firebase déjà couvertes par le mapper existant d'`AuthProvider`
      (`email-already-in-use` → `AppError.emailInUse`,
      `username-already-in-use` → `AppError.usernameInUse`,
      `credential-already-in-use` → tombe en `AppError.authFailed` par défaut — à
      affiner si l'UX le demande).
- [x] **Vérifs** : `flutter analyze` clean · **144/144 tests verts** (aucun cassé) ·
      `dart format` propre sur les deux fichiers touchés.

#### 3. AuthProvider — état `anonymous` + auto sign-in ✅ (2026-06-24)
- [x] `AuthStatus.anonymous` ajouté à l'enum (avec docstring : pas de profil, mur
      d'upgrade côté UI).
- [x] `_onAuthStateChanged(user)` réécrit :
      - `user == null` + flag `_anonymousSignInAttempted == false` → status `unknown`,
        appel `signInAnonymously()`. Le listener re-fire avec le User anonyme (cas
        nominal) **ou** on bascule en `unauthenticated` + `AppError.networkRequestFailed`
        (échec offline). Le flag interdit le retry auto = pas de boucle.
      - `user.isAnonymous` → `AuthStatus.anonymous`, profile null, **pas de fetchProfile,
        pas de registerForUser** (cohérent avec règles : un anonyme ne peut pas écrire
        `devices/`).
      - `user.isAnonymous == false && !user.emailVerified` → `awaitingVerification`
        (chemin post-upgrade).
      - `user.isAnonymous == false && user.emailVerified` → fetchProfile + route legacy
        intacte.
- [x] `bool get isAnonymous` exposé sur le provider.
- [x] `Future<bool> upgradeWithEmail(...)` : appelle `_service.upgradeAnonymous`, log
      `AnalyticsService.logSignUp`, puis **rejoue manuellement** `_onAuthStateChanged
      (currentUser)` car `linkWithCredential` ne déclenche pas toujours `authStateChanges`
      (uid inchangé = pas un sign-in event au sens Firebase). Mappe
      `email-already-in-use` / `username-already-in-use` via `_codeFor`.
- [x] `Future<bool> retryAnonymousSignIn()` exposé pour le bouton « Réessayer » de
      l'écran `unauthenticated`.
- [x] `logout()` **réarme `_anonymousSignInAttempted = false`** avant `signOut()` →
      la nouvelle session anonyme démarre automatiquement après. C'est aussi le mécanisme
      derrière « Effacer cette session anonyme » (Paramètres).
- [x] `AuthGate` : ajout du case `AuthStatus.anonymous` → MainShell (même
      `ChangeNotifierProxyProvider<RegionProvider, ReportProvider>` que `authenticated`).
      `unauthenticated` reste sur `LoginScreen` pour l'instant (TODO task-4 :
      écran « Réessayer »).
- [x] **Tests provider** (6 nouveaux dans `test/auth_provider_test.dart`) :
      1. État initial (user null) → `signInAnonymously` appelé exactement 1 fois,
         status `unknown` (le mock stream ne réémet pas le user anonyme).
      2. Échec auto sign-in → `unauthenticated` + `AppError.networkRequestFailed`,
         pas de retry auto (vérifié via `verify(...).called(1)`).
      3. `retryAnonymousSignIn` succès après échec initial → 2 appels au total.
      4. `upgradeWithEmail` succès → ok + analytics + délégation correcte au service.
      5. `upgradeWithEmail` `email-already-in-use` → `AppError.emailInUse`.
      6. `upgradeWithEmail` `username-already-in-use` → `AppError.usernameInUse`.
- [x] **Vérifs** : `flutter analyze` clean · `dart format` clean · **149/149 tests verts**
      (4 nouveaux sur 145).

#### 4. AuthGate — routing ✅ (2026-06-24)
- [x] Case `AuthStatus.anonymous` → MainShell (mêmes providers que `authenticated`).
      Déjà posé en tâche 3 pour faire passer `flutter analyze`.
- [x] Case `AuthStatus.unauthenticated` → nouvel écran [`AnonymousRetryScreen`]
      (`lib/screens/anonymous_retry_screen.dart`) :
      - Icône `wifi_off_rounded`, heading + body explicatifs.
      - Affichage de `auth.error` (localisé via `appErrorLabel`) si présent.
      - CTA primaire « Réessayer » → `retryAnonymousSignIn()` (spinner pendant `busy`).
      - CTA secondaire « J'ai déjà un compte » → push de `LoginScreen` (Navigator).
- [x] `LoginScreen` retiré des imports d'`auth_gate.dart` (plus utilisé directement
      — il reste accessible via la navigation depuis `AnonymousRetryScreen`, et plus
      tard depuis le mur d'upgrade du Profil).
- [x] **i18n FR/EN** : 5 nouvelles clés `anonymousRetryTitle`, `anonymousRetryHeading`,
      `anonymousRetryBody`, `anonymousRetryButton`, `anonymousRetryAlreadyAccount`.
      `flutter gen-l10n` régénéré.
- [x] **Vérifs** : `flutter analyze` clean · `dart format` clean · **149/149 tests verts**.

#### 5. RegionProvider — fallback anonyme ✅ (2026-06-24)
- [x] **Constat** : la chaîne de résolution actuelle (override → GPS → home → locale → `CM`)
      gère DÉJÀ le cas anonyme correctement. `app.dart` appelle
      `region.setHomeCountry(auth.profile?.homeLocation.country)` → `null` quand `profile`
      est `null` (anonyme) → `_homeCountryIso = null` → fallback chaîne naturelle.
- [x] Docstring `setHomeCountry` enrichie pour expliciter le cas session anonyme et le
      fallback dégradé (lib/providers/region_provider.dart:106).
- [x] **Tests ajoutés** (`test/region_provider_test.dart`, 5 cas, mock SharedPreferences
      + LocationRepository.denied) :
      1. `setHomeCountry(null)` ne plante pas après un précédent country.
      2. Sans override/profil/GPS, `activeCountry` reste valide (ISO ≤ 3 char).
      3. **Override dev gagne** sur l'absence de profil (test du sélecteur dev en
         session anonyme).
      4. Transition anonyme → upgrade : `setHomeCountry('Cameroun')` ⇒ `activeCountry == 'CM'`.
      5. Documentation : `GeoArea().country == ''` (sentinel utilisé côté `auth_provider`).
- [x] **Vérifs** : `flutter analyze` clean · **154/154 tests verts** (5 nouveaux).

#### 6. ProfileScreen — mur d'upgrade (mur + accès Paramètres) ✅ (2026-06-24)
- [x] `ProfileScreen` lit `auth.isAnonymous` → bascule entre le profil classique et le
      nouveau widget privé `_UpgradeWall` :
      - Icône `account_circle_outlined`, heading + body explicatifs.
      - 4 lignes de bénéfices avec icônes (profil, stats, suivi quartiers, notifs).
      - CTA primaire « Créer un compte » → push `UpgradeAccountScreen` (stub minimal posé
        pour ce ticket, formulaire réel = tâche 9).
      - CTA secondaire « J'ai déjà un compte » → **AlertDialog de confirmation** rappelant
        que les votes/signalements anonymes ne seront PAS rattachés au compte existant
        (Firebase ne fusionne pas deux uids) avant de push `LoginScreen`.
- [x] **AppBar du Profil** : icône Paramètres TOUJOURS accessible (y compris en anonyme).
      Icône Edit cachée en anonyme (déjà guardée par `if (profile != null)`).
- [x] StatsScreen, FollowQuartier, EditProfile, AccountSecurity : automatiquement
      inaccessibles en anonyme car routés depuis les tuiles de l'ancien profil — qui ne
      s'affichent plus.
- [x] `SettingsScreen` adapté :
      - Section « Notifications » + toggle FCM cachés en anonyme (pas de ciblage possible
        sans homeLocation/quartiers suivis).
      - Section « Compte » : `_DeleteAccountTile` remplacé par `_ResetAnonymousSessionTile`
        (« Effacer cette session anonyme ») en anonyme. La tuile montre un AlertDialog
        de confirmation, appelle `auth.logout()` (qui réarme `_anonymousSignInAttempted` →
        le listener démarre une nouvelle session anonyme automatiquement), puis
        `Navigator.popUntil(isFirst)`.
- [x] `UpgradeAccountScreen` placeholder créé (`lib/screens/upgrade_account_screen.dart`,
      icône `construction_outlined` + i18n `upgradeAccountComingSoon`). Sera complété en
      tâche 9 avec le formulaire `auth.upgradeWithEmail(...)`.
- [x] **i18n FR/EN** : 14 nouvelles clés (`profileUpgradeWall*` ×9, `upgradeAccount*` ×2,
      `settingsResetAnonymousSession*` ×3). `flutter gen-l10n` régénéré.
- [ ] **À FAIRE en tâche 9** : remplir `UpgradeAccountScreen` (formulaire +
      `auth.upgradeWithEmail`).
- [ ] **À FAIRE en tâche 7** : sur les toggles « suivre ce quartier » (officiels Eneo
      side / map), intercepter le clic anonyme → bottom-sheet upgrade.
- [x] **Vérifs** : `flutter analyze` clean · `dart format` clean · **154/154 tests verts**.

#### 7. ReportCard / création de report par anonyme ✅ (2026-06-24)
- [x] `ReportProvider.submitReport` / `createFromDraft` : **aucun changement** — utilisent
      `auth.uid` (présent en anonyme) et l'`authorUsername` passé par le formulaire (qui
      vaut `null` quand `profile == null`).
- [x] **`ReportCard` inchangé** : le bloc existant
      `if (report.authorUsername != null && report.authorUsername!.isNotEmpty)` couvre
      déjà le cas anonyme → AUCUNE référence à l'auteur n'est affichée (banalisation).
      Test ajouté pour figer cet invariant (`test/report_card_test.dart`, 3 cas :
      null → rien, vide → rien, renseigné → `@username`).
- [x] **Bottom-sheet « Garde tes signalements »** créée
      (`lib/widgets/anonymous_first_report_sheet.dart`) :
      - Widget `AnonymousFirstReportHintSheet` : icône `bookmark_added_outlined`,
        titre + corps, CTA primaire « Créer un compte » → `UpgradeAccountScreen`,
        CTA secondaire « Plus tard » → ferme.
      - Helper `showAnonymousFirstReportHintIfNeeded(BuildContext)` :
        * No-op si `auth.isAnonymous == false`.
        * No-op si SharedPrefs key `anonymous_first_report_hint_seen` déjà à `true`.
        * Sinon : pose le flag (AVANT d'afficher la modale → idempotent même si l'user
          déclenche un 2ᵉ report très vite), puis `showModalBottomSheet`.
- [x] **Branchement** dans `report_form_screen.dart` (`_finish`) : sur succès, capture du
      `rootNavigator.context` AVANT le pop de la modale formulaire, puis appel
      non-bloquant à `showAnonymousFirstReportHintIfNeeded(rootContext)`. Le `rootContext`
      reste valide car le navigator parent vit au-dessus de la modale.
- [x] **i18n FR/EN** : 4 clés `anonymousFirstReportHint{Title,Body,CTA,Later}`.
      `flutter gen-l10n` régénéré.
- [x] **Tests** : 3 nouveaux dans `test/anonymous_first_report_sheet_test.dart` :
      1. Session non anonyme → no-op, flag NON posé.
      2. Anonyme + flag absent → flag posé + sheet affichée.
      3. Anonyme + flag déjà posé → sheet NON rejouée.
- [x] **Vérifs** : `flutter analyze` clean · `dart format` clean · **160/160 tests verts**
      (6 nouveaux : 3 ReportCard + 3 sheet).

#### 8. NotificationService — N/A en anonyme ✅ (2026-06-24)
- [x] **Vérifié** : `_onAuthStateChanged` ne touche pas `_notifications.registerForUser`
      quand `user.isAnonymous == true` (verrouillé en tâche 3, branche dédiée). Idem
      pour `unregister()` qui est idempotent + silencieux.
- [x] **Vérifié** : règles Firestore refusent déjà la création de `devices/{token}` en
      anonyme (`!isAnonymous()`, posé en tâche 1) → double garde-fou si jamais le code
      tentait quand même un upsert.
- [x] **Bug latent corrigé** : `refreshVerification()` mettait à `authenticated` sans
      appeler `registerForUser`. Conséquence : après upgrade + vérif email, l'utilisateur
      ne recevait aucune notif tant qu'il n'avait pas redémarré l'app (l'auth listener
      n'est rappelé qu'à l'init). Idem pour le `register` legacy. Fix : à la transition
      vers `authenticated`, on appelle `registerForUser` directement quand `profile != null`.
- [x] **Test ajouté** (`auth_provider_test.dart` → `refreshVerification (post-upgrade)
      → registerForUser appelé`) : mock du `User` avec `emailVerified == true`,
      vérification que `notifications.registerForUser(userId, homeLocation)` est appelé
      exactement 1 fois.
- [x] **Vérifs** : `flutter analyze` clean · `dart format` clean · **161/161 tests verts**
      (1 nouveau).

#### 9. UpgradeAccountScreen (nouvel écran) ✅ (2026-06-24)
- [x] Formulaire complet (prénom, nom, pseudo unique, email, mdp + confirmation, tél +
      indicatif via `IntlPhoneField` CM par défaut, naissance, acceptation CGU). Reprend
      la structure de `RegisterScreen` pour cohérence UX/accessibilité.
- [x] Bandeau d'intro en haut du formulaire (chip ambre avec icône check) :
      « Tes signalements et votes restent attachés à ton nouveau compte. »
- [x] `_submit` :
      1. Validate form + acceptation CGU.
      2. Pré-check pseudo via `auth.isUsernameAvailable`.
      3. `auth.upgradeWithEmail(...)` (= `linkWithCredential` → uid préservé).
      4. **Succès** : `Navigator.pop(context)` — l'AuthGate observe `awaitingVerification`
         et bascule automatiquement vers `EmailVerificationScreen`.
      5. **Erreur `AppError.emailInUse`** : AlertDialog dédié explicitant que les votes
         anonymes ne seront PAS rattachés au compte existant ; CTA « Se connecter » →
         `pushReplacement(LoginScreen())` (pour ne pas empiler sur l'upgrade).
      6. **Autres erreurs** : snack standard via `appErrorLabel`.
- [x] **i18n FR/EN** : 4 clés ajoutées (`upgradeAccountIntro`, `upgradeAccountSubmit`,
      `upgradeAccountEmailInUseTitle`, `upgradeAccountEmailInUseBody`).
      `upgradeAccountComingSoon` supprimée (plus de placeholder).
- [x] **Vérifs** : `flutter analyze` clean · `dart format` clean · **161/161 tests verts**
      (le formulaire en lui-même n'a pas de test dédié — couverture par le smoke test
      manuel à exécuter sur l'émulateur).

#### 10. i18n FR/EN — récap final ✅ (2026-06-24)
- [x] **28 clés ajoutées au total** (FR + EN, vérifiées synchrones par diff) :
      - **Récup connexion** (tâche 4, ×5) : `anonymousRetryTitle`,
        `anonymousRetryHeading`, `anonymousRetryBody`, `anonymousRetryButton`,
        `anonymousRetryAlreadyAccount`.
      - **Mur d'upgrade Profil** (tâche 6, ×10) : `profileUpgradeWallHeading`,
        `profileUpgradeWallBody`, `profileUpgradeWallBenefit{Profile,Stats,Follow,Notifs}`,
        `profileUpgradeWallCTA`, `profileUpgradeWallAlreadyAccount`,
        `profileUpgradeWallLoginWarning{Title,Body}`.
      - **Reset session Paramètres** (tâche 6, ×4) : `settingsResetAnonymousSession`,
        `settingsResetAnonymousSession{Title,Body,Confirm}`.
      - **Bottom-sheet 1ᵉʳ report** (tâche 7, ×4) : `anonymousFirstReportHint{Title,Body,
        CTA,Later}`.
      - **UpgradeAccountScreen** (tâche 9, ×5) : `upgradeAccountTitle`,
        `upgradeAccountIntro`, `upgradeAccountSubmit`, `upgradeAccountEmailInUse{Title,Body}`.
- [x] ⚠️ Décision finale : **pas de clé `reportAnonymousAuthor`** — les reports anonymes
      n'affichent AUCUN auteur (banalisation, cf. tâche 7).
- [x] `flutter gen-l10n` régénéré ; aucun warning. Diff FR/EN clean.

#### 11. Analytics ✅ (2026-06-24)
- [x] 4 méthodes ajoutées à `AnalyticsService` :
      - `logAnonymousStarted()` → `anonymous_started`.
      - `logAnonymousFirstReport()` → `anonymous_first_report`.
      - `logUpgradeStarted()` → `upgrade_started`.
      - `logUpgradeCompleted()` → `upgrade_completed`.
- [x] **Branchement** :
      - `anonymous_started` : émis dans `AuthProvider._onAuthStateChanged` à la 1ʳᵉ
        transition vers `AuthStatus.anonymous`. Flag local `_anonymousStartedLogged`
        évite les doublons (rotation token, reload session) ; réarmé par `logout()`
        → une nouvelle session anonyme post-reset compte comme un nouvel utilisateur
        du funnel.
      - `anonymous_first_report` : émis dans `showAnonymousFirstReportHintIfNeeded`
        en même temps que le flag SharedPrefs est posé (atomique, 1 fois par appareil).
      - `upgrade_started` : émis dans `UpgradeAccountScreen.initState` (intention).
      - `upgrade_completed` : émis dans `AuthProvider.upgradeWithEmail` après succès,
        en parallèle du `logSignUp()` standard (distingue le funnel upgrade du flow
        register direct).
- [x] **Tests** (`test/analytics_service_test.dart`, 4 nouveaux) : un par méthode,
      verify de l'event name + paramètres `null`.
- [x] **Lecture funnel attendue** (Firebase Analytics console, post-déploiement) :
      `anonymous_started` (cohort) → `anonymous_first_report` (engagement) →
      `upgrade_started` (intention) → `upgrade_completed` (succès). Taux de conversion
      = `upgrade_completed / anonymous_started`.
- [x] **Vérifs** : `flutter analyze` clean · `dart format` clean · **165/165 tests verts**
      (4 nouveaux).

#### 12. Tests — récap ✅ (2026-06-24)
- [x] **Rules** (`rules_tests/test/firestore.spec.js`, 6 nouveaux + helper
      `asAnonymous`) : anonyme peut create reports, anonyme peut voter atomique,
      anonyme refusé sur `users`/`usernames`/`devices`, régression upgrade
      (sign_in_provider ≠ anonymous → OK).
- [x] **AuthProvider** (`test/auth_provider_test.dart`, 7 nouveaux) :
      - état initial (user null) → `signInAnonymously` appelé 1×.
      - échec sign-in anonyme → `unauthenticated` + `AppError.networkRequestFailed`,
        pas de retry auto.
      - `retryAnonymousSignIn` succès après échec → 2 appels au total.
      - `upgradeWithEmail` succès → délégation au service + analytics.
      - `upgradeWithEmail` `email-already-in-use` → `AppError.emailInUse`.
      - `upgradeWithEmail` `username-already-in-use` → `AppError.usernameInUse`.
      - `refreshVerification` post-upgrade → `registerForUser` appelé.
- [x] **RegionProvider** (`test/region_provider_test.dart`, 5 nouveaux) : fallback
      anonyme (setHomeCountry null), override dev qui gagne, transition
      anonyme → upgrade.
- [x] **ReportCard** (`test/report_card_test.dart`, 3 nouveaux) : authorUsername
      null/vide → AUCUNE référence à l'auteur ; renseigné → `@username` affiché.
- [x] **Bottom-sheet 1ᵉʳ report** (`test/anonymous_first_report_sheet_test.dart`,
      3 nouveaux) : non anonyme = no-op ; anonyme + flag absent = posé + affichée ;
      flag déjà posé = pas rejouée.
- [x] **Analytics** (`test/analytics_service_test.dart`, 4 nouveaux) : 1 test par
      nouvelle méthode du funnel.
- [x] **Widget ProfileScreen** (`test/profile_screen_test.dart`, 2 nouveaux) :
      - anonyme → mur d'upgrade visible (heading + CTAs), profil masqué, icône
        Edit cachée, icône Paramètres présente.
      - authentifié + profil → profil classique, mur masqué, icône Edit visible.
- [x] **Smoke tests manuels** : section ajoutée à `tasks/TESTS-MANUELS.md`
      avec 8 scénarios bout-en-bout (install fraîche → 1ᵉʳ report → vote →
      profil → reset session → upgrade → email-déjà-utilisé → offline) +
      pièges connus (App Check, reinstall = nouvel uid).

**Bilan final** : `flutter analyze` clean · `dart format` clean ·
**167/167 tests Flutter verts** (+30 nouveaux) · **37/37 tests rules verts**
(+6 nouveaux).

### Acceptation
- `flutter analyze` clean · `flutter test` vert (nouveaux tests inclus).
- **Smoke test manuel** ajouté à `tasks/TESTS-MANUELS.md` :
  1. Install fraîche → écran d'accueil sans login (anonyme transparent).
  2. Création d'un report sans login → visible sur carte/liste, étiqueté « Anonyme ».
  3. Confirmation/restoration d'un autre report → OK.
  4. Onglet Profil → mur d'upgrade visible.
  5. Flow « Crée un compte » → mail de vérification → retour app → tous les anciens
     reports/votes anonymes toujours attachés au nouvel uid.
  6. Tentative upgrade avec email déjà utilisé → message clair, pas de plantage.

### Risques connus
- **Réinstall = nouvel uid anonyme** → bot peut respawn. Mitigation v1 : App Check ; v2 :
  cap reports/uid/jour Cloud Function.
- **Boucle `signInAnonymously` offline** → flag « pas de retry auto », bouton retry manuel.
- **`email-already-in-use` sur upgrade** → message explicite, pas de fusion auto (Firebase
  ne sait pas fusionner deux uids).

### Hors scope étape 1
- Ouverture lecture publique sans aucune auth (étape 2).
- Ajout service Eau (étape 3).
- Rate limit Cloud Function reports/uid/jour (mitigation différée).

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
      - [x] Placeholders remplis (éditeur **Bogal Consulting**, contact `bogal.consulting@gmail.com`,
            Analytics ajouté) + date MAJ 14 juin 2026.
      - [x] **CGU** (`public/cgu.html`) et **Mentions légales** (`public/mentions-legales.html`)
            créées, bilingues FR/EN, liées entre elles (footer). ⚠️ Brouillons à **faire relire par un
            juriste** ; compléter dans `mentions-legales.html` l'**adresse postale + immatriculation**
            de l'éditeur (placeholder « À compléter »).
      - [ ] **AVANT soumission store** : relecture juriste + `firebase deploy --only hosting` (Node ≥20)
            pour publier privacy + cgu + mentions-legales. (Optionnel : lien in-app vers CGU.)
- [x] **Suppression de compte (RGPD / exigence stores)** : Cloud Function callable `deleteAccount`
      (anonymise les signalements ; supprime profil/pseudo/devices/médias/compte Auth) +
      UI `Profil → Paramètres → Compte → Supprimer mon compte` (ré-auth mot de passe) +
      page web `https://lightcutoff-dev.web.app/account-deletion` pour le Data Safety.
      Fonction + hosting **déployés**. analyze clean, 114 tests verts, functions 10/10.
      *Différé explicitement (« pas maintenant »).*

### 🟠 Important (qualité / robustesse)
- [x] **🔒 Durcir la règle Firestore des compteurs (trou anti-faux)** ✅ *(2026-06-13)*
      - **Était** : la règle contrôlait *quels* champs changent, pas la *valeur* → n'importe quel
        user connecté pouvait écrire `confirmationCount = 9999` sans déposer de vote.
      - **Fix (option A, minimale)** : `firestore.rules` — un tiers ne peut faire que **+1** sur un
        compteur (`bumpsCounterByOne`) **et** seulement en créant son propre vote dans le **même
        commit atomique** (`castsVote` via `exists`/`existsAfter`), pas deux fois, pas sur sa propre
        coupure pour `confirmationCount`. Le chemin client (transaction vote+compteur) reste valide.
      - **Vérifié** : `rules_tests/` (31 verts) — valeur arbitraire refusée, +1 sans vote refusé,
        double vote refusé, vote légitime atomique accepté. **Déployé sur lightcutoff-dev.**
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
- [ ] **🗺️ Cartographier l'étendue d'une coupure (via positions des confirmants)** — DESIGN validé
      (2026-06-14). Idée : 1 signalement = 1 point, mais N confirmations venant d'endroits différents
      = l'emprise réelle. Représentation = **cercle de zone estimée** (CircleLayer).
      - **Vie privée** : on stocke la **cellule geohash ~1,2 km** du confirmant (PAS de GPS précis),
        cohérent avec « cellules anonymes ». Confirmation sans localisation = compte quand même, ne
        contribue pas à l'étendue.
      - **Anonymat préservé** : les confirmations restent lisibles auteur/admin seulement. Une Cloud
        Function **`onConfirmationCreated`** recopie la cellule dans un champ **public agrégé**
        `extentCells` (set/comptes) sur le report ; la carte lit `extentCells`, jamais les votes.
      - **Cercle** : centre = barycentre {point du report + centres des cellules}, rayon = distance
        au plus loin + marge, **plancher ~400 m**, opacité/couleur = nb de cellules (confiance).
      - **Rendu (choisi, maquette validée 2026-06-14)** : **cercle SEUL** à l'écran (+ point d'origine
        + chip « N confirmations »). Les **cellules ne sont PAS dessinées** (trop chargé) — elles
        restent un détail de calcul interne, éventuellement révélable en outil dev. La confiance se
        lit via l'**opacité/bordure** du cercle, pas via des carrés.
      - **Touche** : modèle `confirmations` (+geohash) ; `confirmReport` (capte la cellule via
        LocationService) ; rules (champ + interdire écriture client de `extentCells`) ; Cloud Function
        d'agrégation ; politique de confidentialité (cellule approx. du confirmant) ; carte (CircleLayer
        + calcul d'emprise en fonction pure testée) ; gestion refus localisation.
      - **⚠️ Honnêteté** : afficher « zone estimée » ; rayon dérivé de la dispersion réelle, jamais
        inventé. Cold-start : peu de confirmants = petit cercle pâle (confiance faible).
- [x] **🗑️ Suppression d'un signalement par son auteur + RAISON** ✅ (2026-06-15) : dialog avec
      choix de raison obligatoire (erreur / doublon / courant revenu / autre), stockée en
      `archiveReason` sur le report (`archiveReport(reportId, {reason})`). ⚙️ **Cron de purge
      `purgeArchivedReports` DÉSACTIVÉ** (`PURGE_ARCHIVED_ENABLED=false`, déployé) → les reports
      archivés ne sont plus supprimés définitivement pour l'instant. Reste possible : version
      antérieure ci-dessous.
- [ ] ~~Suppression + raison (spec d'origine)~~ : la suppression existe déjà
      (`archive` / soft-delete `archivedAt`, auteur uniquement, écran détail). **Ajout demandé** :
      au moment de supprimer, **demander la raison** (« erreur de saisie », « doublon », « courant
      déjà revenu », « autre » + texte libre optionnel). Stocker la raison sur le report
      (`archiveReason`) pour la modération / comprendre pourquoi les gens suppriment.
      - Touche : dialog de suppression (`report_detail_screen._confirmAndArchive`) → ajouter le choix
        de raison ; `archiveReport` (+ champ `archiveReason`) ; rules (autoriser le champ) ; i18n FR/EN.
      - ⚠️ Garde-fou : ne pas transformer ça en outil pour **masquer une vraie coupure** — la
        suppression reste réservée à l'**auteur** ; les coupures confirmées par d'autres pourraient
        rester visibles ou nécessiter un seuil (à décider).
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

- [x] **1. Statistiques utilisateur sur ses données de coupures** ✅ *(palier 0 — faible risque)*
  - **Pourquoi** : rendre à l'utilisateur une info perso à forte valeur (réciprocité) — il revient
    pour **sa** donnée. Aucune prédiction → aucune fausse promesse, utile même à faible volume.
  - **Livré (2026-06-13)** : logique pure `lib/utils/outage_stats.dart` (compte, durée
    moyenne/cumulée sur coupures **rétablies** uniquement, répartition par heure + par jour, pics) ;
    `StatsProvider` (mes coupures via `reportsByAuthor`, ma zone via `reportsWithinRadius` rayon
    `notifyRadiusMeters` ≈ 2 km autour de la position) ; écran `stats_screen.dart` (cartes +
    histogrammes maison, états vide/indisponible/erreur) ; entrée Profil ; i18n FR/EN ; event
    analytics `stats_viewed`. `reportsByAuthor` ajouté au repo/service (requête champ unique).
  - **Vérifié** : `flutter analyze` clean · **134 tests verts** (7 nouveaux sur la logique pure :
    vide, durée rétablie-only, durée négative ignorée, moyenne, histos heure/jour, pics).
  - ⏳ **Reste** : smoke test visuel sur appareil/émulateur (rendu + état vide à faible volume).

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

## ✅ Plancher d'auto-résolution = 3 sur staging (2026-06-13)
- [x] Seuil **remis à 3** sur staging — fixé **explicitement** via
      `functions/.env.lightcutoff-dev` (`RESTORATION_MIN_VOTES=3`), pas par suppression du fichier :
      Firebase ne supprime pas une env var déjà posée sur Cloud Run (elle était restée à 1 → bug
      « résolu dès 1 vote »). Vérifié sur la fonction déployée (`environmentVariables` = 3).
      Pour re-tester à 1 compte : passer la valeur à 1, redéployer, puis remettre 3.

## 📌 À faire tout de suite (housekeeping)
- [ ] **Pousser** la branche : `master` est **ahead 1** (commit i18n `c22f253`) — pas encore sur `origin`.
- [ ] **Commiter `CLAUDE.md`** (actuellement non suivi).

---

## 🌍 Environnements (dev / staging / prod) — ✅ câblés côté app (2026-06-10)

> `--dart-define=APP_ENV=dev|staging|prod` (`AppConfig.environment`).
> **dev** = émulateurs locaux · **staging** = `lightcutoff-dev` en ligne (outils dev visibles même
> en release : sélecteurs langue + pays/compagnie, bannière STAGING) · **prod** = projet dédié.
> Rétro-compat : sans `APP_ENV` → staging ; `USE_EMULATOR=true` → dev. `main()` **refuse**
> `APP_ENV=prod` tant que le projet n'existe pas. Alias `.firebaserc` : `staging` → lightcutoff-dev.

### 📋 Checklist « jour de création du projet PROD » (rien n'existe encore)
- [ ] Créer le projet Firebase prod (ex. `njuka-prod`) — compte `willkoua@gmail.com`, Blaze.
- [ ] `flutterfire configure --project=<prod> --platforms=android,ios --out=lib/firebase_options_prod.dart`
      puis brancher la sélection d'options dans `main.dart` (lever la garde `isProd`).
- [ ] `.firebaserc` : ajouter l'alias `prod`.
- [ ] Déployer **règles + functions + hosting** sur prod (`firebase deploy -P prod`) — règles ET
      functions ENSEMBLE (leçon du 2026-06-10).
- [ ] Lancer une 1ʳᵉ ingestion Eneo sur prod (cron ou `gcloud scheduler jobs run`).
- [ ] App Check : enregistrer l'app Android prod (Play Integrity + SHA-256) ; debug token au besoin.
- [ ] Play Console : pointer les releases store sur un AAB buildé `--dart-define=APP_ENV=prod`
      (+ STADIA_API_KEY) ; récupérer la SHA-256 Google (Play App Signing) → Firebase + App Check.
- [ ] Vérifier qu'aucun outil dev n'apparaît (pas de bannière, pas de sélecteurs en Paramètres).

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
