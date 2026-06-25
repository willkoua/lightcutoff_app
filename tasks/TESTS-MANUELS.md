# Tests manuels (smoke tests)

## Ingestion Eneo — écriture émulateur bout-en-bout (V1 backend) ✅

> Vérifie l'écriture réelle dans Firestore (`official_outages/`), la déduplication et la purge.
> On lance l'ingestion en **appel direct** via un script (`functions/scripts/seedEneo.cjs`), **pas**
> via un déclencheur HTTP : le worker HTTPS de l'émulateur firebase-tools plante avec
> firebase-functions v7 (« functions.config() removed » → « Failed to load function »). Le cron de
> prod `ingestEneoOutages` n'est pas concerné.

### Recette rapide (headless)
```bash
cd ~/Desktop/Projets/lightcutoff/lightcutoff_app
(cd functions && npm run build)
firebase emulators:exec --only firestore --project lightcutoff-dev \
  "node functions/scripts/seedEneo.cjs"
```
Sortie attendue (le `fetch` appelle le vrai Eneo → nécessite internet) :
```
Ingestion: {"upserted":~650,"pruned":0}
Docs écrits: ~650 · quartiers vides: 0
  ex: EST | "BIRPONDO" | 2026-06-13 | 2026-06-13T18:00:00.000Z
```
- [ ] `upserted` ≈ volume du jour, `pruned` cohérent
- [ ] **0 quartier vide**
- [ ] horaires en UTC corrects (06:00 Douala → 05:00Z, etc.)

> ℹ️ Tourne avec le **Node par défaut** (v24) — pas besoin de basculer en Node 22.

### Variante visuelle (inspecter dans l'UI émulateur)
Terminal A :
```bash
cd ~/Desktop/Projets/lightcutoff/lightcutoff_app
(cd functions && npm run build)
firebase emulators:start --only firestore
```
Terminal B (pointer le script vers l'émulateur en cours) :
```bash
cd ~/Desktop/Projets/lightcutoff/lightcutoff_app
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=lightcutoff-dev \
  node functions/scripts/seedEneo.cjs
```
Puis **http://127.0.0.1:4000** → Firestore → collection `official_outages` :
- [ ] ~650 docs, champs `provider/country/region/quartier/progDate/startsAt/endsAt/fetchedAt`
- [ ] relancer le script → le nombre **ne double pas** (idempotence par `rawHash`)

### Notes / pièges
- `npm test` (functions) doit tourner sous le **Node par défaut** : sous un Node forcé via nvm,
  `tsx`/esbuild peut planter (mismatch de binaire) — faux positif, pas une vraie erreur de test.
- `pruned > 0` est normal une fois que des dates Eneo passent (purge des entrées < aujourd'hui).

---

## Migration auth anonyme (pivot 2026-06-24) — recette bout-en-bout

> Préalable : Anonymous Auth activé dans la console `lightcutoff-dev`
> (Auth → Sign-in method) **et** règles Firestore déployées (`firebase deploy
> --only firestore:rules`). Build : `flutter run --dart-define=APP_ENV=staging`
> (ou `dev` pour tester avec les émulateurs).

### Recette
1. **Install fraîche** : désinstaller l'app, relancer → après l'onboarding, on
   atterrit DIRECTEMENT sur la home (carte/liste) **sans login**.
   - [ ] Pas d'écran de connexion.
   - [ ] La carte/liste se charge (lecture possible).

2. **1ᵉʳ signalement anonyme** : FAB → formulaire → submit.
   - [ ] Signalement visible dans la liste/carte.
   - [ ] **Aucune référence à l'auteur** affichée sur la carte (pas de chip
         `@…`, pas de libellé « Anonyme »).
   - [ ] Après pop du formulaire : **bottom-sheet** « Garde tes signalements »
         apparaît (CTA primaire « Créer un compte » + secondaire « Plus tard »).
   - [ ] 2ᵉ signalement : la bottom-sheet ne réapparaît PAS (flag SharedPrefs).

3. **Vote anonyme** : sur un report d'un autre utilisateur, tap « Je confirme »
   puis sur un autre tap « Courant revenu ».
   - [ ] Les compteurs s'incrémentent côté UI.
   - [ ] L'indicateur « tu as déjà voté » apparaît à la place du bouton.

4. **Onglet Profil en anonyme** :
   - [ ] Mur d'upgrade (heading « Tire le meilleur de NJUKA » + 4 bénéfices).
   - [ ] Bouton **Paramètres** accessible en AppBar.
   - [ ] Dans Paramètres : pas de section « Notifications », et la section
         « Compte » affiche **« Effacer cette session anonyme »** au lieu de
         « Supprimer mon compte ».

5. **Reset session anonyme** : Paramètres → « Effacer cette session » → confirm.
   - [ ] L'app remonte à la racine, nouvelle session anonyme crée
         automatiquement (toujours sur la home).
   - [ ] Les signalements de l'ancienne session restent visibles (rattachés à
         l'ancien uid en base), mais on ne peut plus les modifier.

6. **Upgrade vers compte réel** : Profil → « Créer un compte » → formulaire.
   - [ ] Bandeau d'intro ambre rassurant en haut.
   - [ ] Submit → écran de **vérification email** (`EmailVerificationScreen`).
   - [ ] Ouvre le mail (boîte / spams), clique le lien, reviens dans l'app,
         tap « J'ai vérifié mon email ».
   - [ ] Tu atterris sur MainShell + ton profil est posé.
   - [ ] **Critique** : tes signalements et votes anonymes sont TOUJOURS
         attachés à toi (vérifie Profil → Stats : tu vois bien tes coupures
         d'avant l'upgrade).
   - [ ] Notifs push fonctionnent (un signalement créé par un autre user dans
         ton quartier → notif).

7. **Upgrade avec email déjà utilisé** : refais l'upgrade depuis une autre
   session anonyme en réutilisant l'email du compte créé au step 6.
   - [ ] AlertDialog « Email déjà utilisé » avec corps explicatif.
   - [ ] CTA « Se connecter » → `LoginScreen` en `pushReplacement` (pas
         d'empilement).
   - [ ] Sign-in avec ce compte → tu retrouves ton compte original, mais les
         votes/reports de la **nouvelle** session anonyme sont perdus
         (l'avertissement de l'AlertDialog était honnête).

8. **Échec de session anonyme** (offline au 1ᵉʳ lancement) : couper le réseau
   AVANT d'ouvrir l'app fraîchement installée.
   - [ ] L'app affiche `AnonymousRetryScreen` (icône wifi off, message
         d'erreur).
   - [ ] Rétablir le réseau → tap « Réessayer » → entrée nominale dans l'app.
   - [ ] Ou : « J'ai déjà un compte » → `LoginScreen`.

### Funnel analytics attendu (console Firebase, post-recette)
- `anonymous_started` ≥ 1 (step 1, et step 5).
- `anonymous_first_report` = 1 (step 2 uniquement, flag déjà posé sur 2ᵉ
  install).
- `upgrade_started` = nombre de fois où tu ouvres `UpgradeAccountScreen`.
- `upgrade_completed` = 1 (step 6).

### Pièges connus à valider
- [ ] Sur Android emulator, App Check debug token : déjà enregistré pour le
      device. Si Anonymous fail avec `app_check_token_invalid` → re-récupérer
      le token via `logcat | grep DebugAppCheckProvider` et l'enregistrer en
      console.
- [ ] Reinstall = nouvel uid anonyme (perte des reports/votes de l'install
      précédente — comportement accepté du modèle v1). À documenter dans la
      politique de confidentialité quand on publiera la version anonyme.

---

## Multi-service Eau (pivot étape 3) — recette bout-en-bout

> Préalable : versions déployées (pas de migration Firestore — backward
> compat par défaut `electricity` côté lecture). Build :
> `flutter run --dart-define=APP_ENV=staging`.

### Recette
1. **Sélecteur dans le formulaire** : FAB « Signaler » → formulaire ouvert.
   - [ ] Bandeau `SegmentedButton` en tête : « ⚡ Électricité » sélectionné
         par défaut + « 💧 Eau » à côté.
   - [ ] Toggle Eau → l'icône passe à la goutte, soumettre.
   - [ ] Le report apparaît dans la liste avec un **chip bleu « Eau »**.

2. **Filtre service liste/carte** : retour Home, segmented control Tout /
   ⚡ / 💧 visible en tête.
   - [ ] Tap « 💧 » → seuls les reports Eau s'affichent.
   - [ ] Tap « ⚡ » → seuls les reports Électricité.
   - [ ] Tap « Tout » → mixte.
   - [ ] Quitter l'app, relancer → le dernier choix est **rejoué** (persisté).

3. **Marqueurs carte** : ouvre l'onglet Carte.
   - [ ] Marqueurs ambre + petite icône ⚡ centrée = électricité en cours.
   - [ ] Marqueurs bleu sky + petite icône 💧 centrée = eau en cours.
   - [ ] Marqueurs verts = rétabli (les deux services partagent le vert).
   - [ ] Le filtre 💧 cache les marqueurs ⚡ (et inversement).

4. **Anti-doublon par service** : crée un report Eau à un endroit, puis
   re-signal à proximité.
   - [ ] La popup « coupure à proximité » apparaît AVEC le service indiqué
         dans son chip (cohérent).
   - [ ] Confirmer la coupure existante → compteur OK.

5. **Auto-résolution croisée** : 3 users (anonymes ou non) déclarent
   « courant revenu » sur un report Eau.
   - [ ] Le status bascule en « rétabli » (même seuil
         `restorationMinVotes`/`restorationRatio` qu'élec — service-agnostique).
   - [ ] Le marqueur passe au vert (icône 💧 conservée).

6. **Stats split par service** : Profil → Statistiques.
   - [ ] Le segmented control en tête (commun avec la liste/carte) :
         changement de filtre = recalcul à la volée des stats
         « Mes coupures » et « Ma zone » (pas de spinner).
   - [ ] Élec → ne montre que les coupures élec ; Eau → idem.

7. **Sélecteur dev de fournisseur** : Paramètres → « Pays/Compagnie ».
   - [ ] Dialog affiche Eneo · Cameroun ET **CAMWATER · Cameroun**.
   - [ ] Choisir CAMWATER → l'override s'applique uniquement au service
         eau (le chemin Eneo pour les coupures planifiées reste).

### Régression rétro-compat
- [ ] Reports créés AVANT l'étape 3 (pas de champ `serviceType` en base) :
      apparaissent comme **électricité** (default lecture
      `ServiceType.fromName(null) == electricity`). Vérifier sur un report
      historique connu.

### Pièges connus
- Volume MVP : pas d'index Firestore composite pour `serviceType` — le
  filtre est appliqué client-side. À surveiller si le nombre de reports
  croît au-delà de la pagination courante (`reportsPageSize = 20`).
- L'ingestion Eneo continue de poser `serviceType = electricity` côté
  Cloud Function (par défaut côté modèle `CanonicalOutage`/normalize).
  L'ouverture d'un adaptateur **CAMWATER** est hors scope étape 3.
