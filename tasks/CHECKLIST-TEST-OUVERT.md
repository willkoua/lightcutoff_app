# Checklist — Passage au TEST OUVERT (NJUKA)

> État au 2026-06-25. « Test ouvert » = piste publique, **passe la revue Google**.
> Android = piste **Test ouvert** sur Play Console. iOS = **TestFlight test externe**
> (revue App Review obligatoire, c'est l'équivalent iOS du test ouvert).
> Légende : **[TOI]** = action manuelle/console (login requis) · **[CODE]** = je peux le faire.

---

## 0. Décision bloquante (préalable à TOUT le reste)
- [ ] **Choix du projet Firebase de prod** — *à trancher* :
  - (a) Créer `lightcutoff` propre (séparation dev/staging/prod), **ou**
  - (b) Promouvoir `lightcutoff-dev` en prod (réutilise tout, mais nom `-dev` définitif + purge des données de test).
  - → Détermine si on a besoin de **product flavors** (cas a, packages distincts) ou non (cas b).

---

## 1. Environnement Firebase prod
- [ ] **[TOI]** Enregistrer l'app **Android** `com.njuka.app` dans le projet prod + SHA-256 upload key
      (`48:F3:2F:23:5B:20:99:AE:9D:35:EA:65:C4:93:ED:AE:81:D1:BD:48:FE:45:DB:5B:70:6A:E6:4D:BF:37:67:0A`)
      → télécharger `google-services.json`.
- [ ] **[TOI]** Enregistrer l'app **iOS** `com.njuka.app` → télécharger `GoogleService-Info.plist`.
- [ ] **[TOI]** `flutterfire configure --project=<prod> --out=lib/firebase_options_prod.dart --platforms=android,ios`.
- [ ] **[CODE]** Alias `prod` → `<prod>` dans `.firebaserc`.
- [ ] **[CODE]** `main.dart` : retirer le `throw` sur `isProd`, initialiser avec `firebase_options_prod.dart`.
- [ ] **[CODE]** Product flavors Gradle + sourcesets (**seulement si décision (a)**).
- [ ] **[TOI/CODE]** Déployer règles + indexes + functions + hosting sur le projet prod :
      `firebase deploy --only firestore,storage,functions,hosting --project <prod>`.
- [ ] **[TOI]** Auditer les **env vars Functions** sur le projet prod (ex. `RESTORATION_MIN_VOTES` — piège déjà rencontré, voir lessons.md).
- [ ] **[TOI]** Si décision (b) : **purger les données de test** (reports/users/votes factices) avant ouverture.

## 2. Sécurité (App Check + secrets)
- [ ] Code App Check : **déjà fait** (Play Integrity / App Attest en release — `main.dart`).
- [ ] **[TOI]** Firebase prod → App Check → enregistrer **Play Integrity** (Android) + **App Attest / DeviceCheck `.p8`** (iOS).
- [ ] **[TOI]** Passer App Check en **« Appliqué » (enforced)** sur Firestore + Functions + Storage
      *après* avoir vérifié que le trafic « vérifié » est majoritaire.
- [ ] **[TOI]** Quand Play App Signing est actif : ajouter dans Firebase la **SHA-256 de la clé de signature Google**
      (Play Console → Intégrité de l'app) — sinon Google Sign-In + App Check cassent en prod.
- [ ] **[TOI]** **Restreindre la clé Stadia Maps** (par package/bundle) dans le dashboard Stadia — elle est embarquée en clair.

## 3. Notifications push
- [ ] **[CODE]** Créer `ios/Runner/Runner.entitlements` avec `aps-environment` + activer Push Notifications (Xcode capability).
- [ ] **[TOI]** Apple Developer → créer la **clé APNs `.p8`** → l'uploader dans Firebase (projet prod).
      ⚠️ Sans ça, **les push iOS ne marchent pas** (bloqueur connu).
- [ ] **[TOI]** Vérifier l'envoi FCM bout-en-bout sur **appareil réel** Android **et** iOS.

## 4. Build & qualité
- [ ] **[CODE]** `flutter analyze` → « No issues found ».
- [ ] **[CODE]** `flutter test` → tout vert.
- [ ] **[CODE]** Bump `version:` dans `pubspec.yaml` (versionCode unique par upload).
- [ ] **[CODE]** Build prod signé :
      `flutter build appbundle --release --dart-define=APP_ENV=prod --dart-define=STADIA_API_KEY=… [--flavor prod]`.
- [ ] **[CODE]** Build iOS : `flutter build ipa --release --dart-define=APP_ENV=prod --dart-define=STADIA_API_KEY=…`.
- [ ] **[TOI]** Smoke test bout-en-bout sur appareil réel (cf. `tasks/TESTS-MANUELS.md`) — build **prod** (sans bannière, sans dev tools).
- [ ] **[TOI]** Vérifier que la **bannière STAGING et les dev tools ont disparu** en build prod.

## 5. Conformité Store (commun, requis par la revue Google/Apple)
- [ ] Pages légales : **déjà rédigées** dans `public/` (`privacy.html`, `cgu.html`, `mentions-legales.html`, `account-deletion.html`).
- [ ] **[TOI/CODE]** Déployer le hosting prod → obtenir l'**URL publique de la politique de confidentialité** (`firebase deploy --only hosting --project <prod>`).
- [ ] **[TOI]** (recommandé) **Relecture juriste** des CGU / politique de confidentialité avant publication.
- [ ] **[TOI]** **Suppression de compte** : URL `account-deletion.html` à renseigner dans Play Console (obligatoire si auth).

## 6. Play Console — Android (Test ouvert)
- [ ] **[TOI]** Fiche du Store complète : titre, description courte/longue, **icône**, **feature graphic** (`store_assets/feature_graphic.png` ✔), **captures** (`store_assets/screenshots/` ✔).
- [ ] **[TOI]** **Classification du contenu** (questionnaire IARC).
- [ ] **[TOI]** **Sécurité des données** (Data Safety) : déclarer localisation, e-mail, identifiants, etc. — cohérent avec la privacy policy.
- [ ] **[TOI]** **Public cible** + déclaration apps gouvernementales/COVID si applicable.
- [ ] **[TOI]** Pays de diffusion (Cameroun + autres ?).
- [ ] **[TOI]** Activer **Play App Signing** (récupérer la SHA-256 Google → §2).
- [ ] **[TOI]** Créer la version **Test ouvert**, uploader l'`.aab` prod, renseigner les notes de version.
- [ ] ⚠️ **[TOI]** Règle Google (comptes perso récents) : **20 testeurs en test FERMÉ / 14 jours continus** exigés *avant l'accès production*. Le test ouvert ne dispense pas de cette étape pour aller plus loin — à anticiper.

## 7. App Store Connect — iOS (TestFlight test externe)
- [ ] **[TOI]** Compte **Apple Developer** (99 $/an) + app créée sur App Store Connect (bundle `com.njuka.app`).
- [ ] **[TOI]** Certificats/profils de distribution + upload de l'`.ipa` (Xcode/Transporter).
- [ ] **[TOI]** Fiche TestFlight + **App Review** (le test externe iOS passe une revue Apple).
- [ ] **[TOI]** Mêmes infos conformité (privacy, data collection) côté Apple.

---

### Ce qui est DÉJÀ prêt
- Code App Check (release providers), règles Firestore durcies (compteurs/votes + geohash), pages légales rédigées,
  feature graphic + captures, geohash des confirmants/rétablissements enregistré.

### Bloqueurs durs avant ouverture
1. Décision projet prod (§0).
2. App Check **enforced** + SHA Google (§2).
3. **APNs iOS** sinon push iOS KO (§3).
4. Build **prod** réel (pas staging) sans dev tools (§4).
5. Data Safety + privacy URL déployée (§5).
6. Étape test **fermé** 14 j si compte perso récent (§6).
