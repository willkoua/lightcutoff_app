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
   - [ ] Mur d'upgrade (heading « Débloque tout le potentiel de NJUKA » +
         3 bénéfices — plus de rangée « Ton profil communautaire »).
   - [ ] Un SEUL bouton : « J'ai déjà un compte » (le bouton « Créer un
         compte » a été retiré du mur le 2026-08-11 ; la création email reste
         accessible via la bottom-sheet post-1er-signalement et LoginScreen).
   - [ ] Bouton **Paramètres** accessible en AppBar.
   - [ ] Dans Paramètres : pas de section « Notifications », et la section
         « Compte » affiche **« Effacer cette session anonyme »** au lieu de
         « Supprimer mon compte ».

5. **Reset session anonyme** : Paramètres → « Effacer cette session » → confirm.
   - [ ] L'app remonte à la racine, nouvelle session anonyme crée
         automatiquement (toujours sur la home).
   - [ ] Les signalements de l'ancienne session restent visibles (rattachés à
         l'ancien uid en base), mais on ne peut plus les modifier.

6. **Upgrade vers compte réel** : bottom-sheet après le 1er signalement
   anonyme → « Créer un compte » → formulaire (le mur du Profil n'a plus ce
   bouton).
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

---

## Signalement sans GPS — « Décrire ma position » (worldwide)

8. **Refus / indisponibilité du GPS au signalement** :
   - [ ] Refuser la permission de localisation, puis taper « Signaler ».
   - [ ] Un dialogue « Position indisponible » s'affiche avec **2 choix** :
         *Autoriser la localisation* et *Décrire ma position*.
   - [ ] Choisir **Décrire ma position** → champ texte (quartier / ville / adresse).
   - [ ] Saisir une ville connue (ex. « Yaoundé », « Paris ») → le signalement
         est créé, le pin apparaît sur la carte au bon endroit.
   - [ ] Vérifier que la **détection de doublon** fonctionne aussi autour du
         point décrit (si une coupure existe déjà à proximité).
   - [ ] Saisir une description bidon (« azerty ») → message **« Lieu introuvable.
         Précise davantage… »**, pas de signalement créé.
   - [ ] **Non-Cameroun** : décrire une ville étrangère → le `countryCode` est
         bien renseigné (cloisonnement par pays respecté), le hint reste générique
         (aucune mention spécifique au Cameroun).

## Conservation de l'historique anonyme — TOUS les types de connexion (2026-07-26)

> Objectif : prouver que Google, Facebook, Apple **et** l'upgrade e-mail
> **conservent les signalements/votes faits en anonyme** (liaison à la session
> anonyme → même uid). Base propre recommandée (purge + `adb shell pm clear
> com.njuka.app` — sinon session zombie, cf. lessons 2026-07-26).

### Recette (à répéter pour CHAQUE méthode : Google · Facebook · Apple (iOS) · E-mail)

1. **En anonyme** (installation fraîche, sans se connecter) :
   - [ ] Créer **1 signalement** (noter le quartier) + **confirmer** une coupure
         existante (seedée au besoin).
   - [ ] Console Firebase → Authentication : noter l'**uid anonyme** ;
         Firestore : `reports/{id}.userId` = cet uid.
2. **Se connecter** : Profil → mur Compte → « J'ai déjà un compte » → la méthode testée.
   - [ ] Le compte social testé est **NEUF** (jamais utilisé sur NJUKA) —
         c'est le cas « liaison ».
   - [ ] Un dialog d'avertissement s'affiche (activité anonyme réelle) et dit
         que l'historique sera **conservé** à la première connexion.
3. **Vérifier la conservation** :
   - [ ] Console Auth : l'uid est **LE MÊME** qu'à l'étape 1 (provider ajouté
         sur la ligne existante, pas de nouvelle ligne ; l'ancienne ligne
         anonyme a disparu).
   - [ ] Profil auto-créé : prénom/nom du provider, **pseudo généré**
         (`prenom_NNN`) annoncé par un snack.
   - [ ] Stats → « Mes coupures » : le signalement de l'étape 1 est là.
   - [ ] Le signalement reste affiché **sans** `@pseudo` (authorUsername
         dénormalisé null à la création — comportement voulu).
   - [ ] Pas d'écran « Vérifie ton email » pour Google/Facebook/Apple
         (vérif réservée au provider `password` ; l'upgrade e-mail, lui,
         DOIT passer par la vérification).
4. **Cas repli (compte social DÉJÀ existant)** — une fois suffit :
   - [ ] Se déconnecter, refaire 1 (nouvelle session anonyme + 1 signalement),
         puis se connecter avec un compte social **déjà rattaché** à un autre
         utilisateur NJUKA → connexion **classique** (changement d'uid), le
         dialog prévient que l'historique anonyme n'est **pas** rattaché.

> ⚠️ Environnements : Apple = iOS uniquement (iPhone réel, backlog validation).
> Google en **prod** ne marchera qu'après le « jour J » OAuth (clients encore
> tenus par lightcutoff-dev) → tester Google sur **staging** d'ici là.

## Pays : détection auto en prod + sélecteur QA (2026-07-28)

> Changement : le **sélecteur de pays** est devenu un outil **dev/staging
> uniquement**. En prod le pays est TOUJOURS détecté : GPS d'abord, **repli
> IP** (`api.country.is`) si la localisation est refusée. Quand un pays est
> sélectionné (QA), le signalement est **rattaché au pays sélectionné** et le
> formulaire l'annonce si ce pays ≠ pays détecté.

### Build prod (détection pure)
1. [ ] Build `APP_ENV=prod` : Paramètres → **aucune tuile « Pays »** (la
       section Région n'apparaît plus ; langue toujours là).
2. [ ] GPS autorisé → la liste montre le pays où tu es ; un signalement créé
       apparaît **immédiatement** dans la liste.
3. [ ] GPS refusé (nouvelle install, refuser la permission) → le pays vient de
       l'**IP** : la liste montre quand même ton pays. ⚠️ Couper le VPN
       (l'IP suivrait le VPN — le GPS, lui, prime toujours quand il existe).
4. [ ] Résidu d'ancien build : même si un pays avait été choisi avant la mise
       à jour, la valeur persistée est **ignorée** en prod.

### Build staging (outil QA)
5. [ ] Paramètres → Région : sélectionner un pays ≠ ta position (ex. Cameroun
       à Montréal).
6. [ ] Ouvrir le formulaire de signalement → **bandeau ambre** : « Pays
       sélectionné : Cameroun. Ta position détectée est ailleurs (Canada) —
       ce signalement sera rattaché à Cameroun. »
7. [ ] Créer le signalement → il **apparaît dans la liste** (rattaché au
       Cameroun), sa ville reste la vraie (ex. Montréal).
8. [ ] Repasser le pays en « Automatique » → plus de bandeau ; le signalement
       suivant est rattaché au pays détecté.

### Formulaire : position décrite PRIORITAIRE avec consentement (2026-08-13)
9.  [ ] Ouvrir le formulaire (GPS autorisé) → la ligne 📍 affiche **ta position
        réelle** ET le bouton **« Décrire ma position »** est visible (il est
        redevenu permanent — décision 2026-08-13 : la description prime sur le
        GPS, avec accord explicite si divergence).
10. [ ] Décrire un lieu **proche** (< 2 km, ex. ton quartier) → retenu
        directement, AUCUN popup (précision, pas de friction).
11. [ ] Décrire un lieu **lointain** (ex. « Douala » depuis Montréal) → popup
        « Position différente du GPS » avec les deux lieux et la distance ;
        **Annuler** → la description est abandonnée (GPS conservé) ;
        recommencer et **« Utiliser ce lieu »** → la ligne passe en 🖊, le
        signalement part au lieu décrit (`positionSource = described`).
12. [ ] GPS refusé/coupé → comportement inchangé : « Position indisponible… »,
        bouton visible, description retenue **sans popup** (rien à comparer).
        Saisie introuvable (« azerty ») → snack « Lieu introuvable ».

## UGC : upload média désactivé + signalement de contenu abusif (2026-07-30)

1. [ ] **Formulaire de signalement** : le bouton « Ajouter une photo/GIF »
       n'apparaît PLUS (désactivé tant qu'aucune modération d'images n'existe
       — `AppConfig.enableReportMedia`). Les médias des anciens reports
       restent visibles sur le détail.
2. [ ] **Détail d'un signalement d'un AUTRE utilisateur** : lien discret
       « ⚑ Signaler ce contenu » en pied de page. Absent sur ses propres
       signalements.
3. [ ] Taper le lien → dialogue avec 4 raisons (abusif / faux / spam / autre
       + champ libre). Envoyer → snack « ton signalement a été transmis ».
4. [ ] Re-signaler le même report → snack « déjà signalé », pas de doublon
       (vérifier en console : `reports/{id}/flags/{uid}` unique, avec
       `reason`).
5. [ ] Analytics : event `report_flagged` (paramètre `reason`).

## Emails personnalisés NJUKA (Brevo) — 2026-08-07

Build staging (ou prod), compte email/mot de passe.

1. **Inscription email** : créer un compte → l'email de vérification reçu doit être
   AUX COULEURS NJUKA (logo, bouton ambre « Confirmer mon email », tutoiement),
   expéditeur `NJUKA <noreply@njuka.app>`. Cliquer le bouton → page de confirmation
   Firebase → retour app → compte vérifié.
2. **Langue** : passer l'app en EN (Paramètres → Langue) → « Renvoyer l'email »
   depuis l'écran de vérification → l'email doit arriver en anglais.
3. **Mot de passe oublié** : depuis l'écran de connexion → email brandé
   « Réinitialise ton mot de passe » → le lien ouvre le formulaire Firebase →
   nouveau mot de passe accepté → reconnexion OK.
4. **Anti-énumération** : demander un reset pour `inexistant@exemple.com` →
   même message de succès dans l'app, AUCUN email reçu.
5. **Upgrade anonyme → email** : depuis une session anonyme, créer le compte via
   le mur Compte → email de vérification brandé reçu (même gabarit qu'en 1).
6. (Boîte à outils) Panne Brevo simulée = repli silencieux sur l'email Firebase
   générique — le parcours ne doit jamais bloquer.

## Carte : zones d'impact (2026-08-07)

Build v64+ (staging), onglet Carte.

1. **Tache autour d'un signalement** : créer un signalement élec → au zoom
   quartier, un disque ambre translucide (~150 m) entoure le pin.
2. **La tache grandit avec les confirmations** : confirmer depuis un 2e
   compte/appareil éloigné de 300-800 m → après quelques secondes (refresh),
   le disque s'étend jusqu'au confirmeur (plafond 2 km).
3. **Couleur service** : un signalement eau → disque bleu ciel.
4. **Fraîcheur** : les taches d'hier sont nettement plus pâles que celles de
   l'heure (données seedées : comparer Bastos [2 h] vs Akwa [14 h]).
5. **Résolues masquées** : résoudre une coupure → sa tache ET son pin
   disparaissent de la carte ; le tiroir de filtres (AppBar) → statut
   « Résolues » les réaffiche (pins verts, pas de tache).
6. **Dézoom ville** : les taches voisines se fondent en nappes — plus de
   ronds compteurs de cluster ; chaque pin reste tapable → détail.

## Partage de signalement (2026-08-08)

Build v66+ (staging).

1. **Bouton** : icône partage en haut à droite d'une carte de signalement →
   feuille native. Le message contient : émoji service, « Coupure … à
   {quartier, ville} », le compteur de confirmations, et le lien.
2. **Lien staging** : `lightcutoff-dev.web.app/s/{id}` → page publique avec
   badge « En cours », compteur, boutons stores. AUCUN pseudo, aucune
   description, aucune position exacte sur la page.
3. **Aperçu WhatsApp** : envoyé dans un chat, le lien montre une vignette
   riche (logo + titre « Coupure … » + description).
4. **Résolue** : partager une coupure résolue → la page montre « ✓ Rétabli ».
5. **Robustesse** : `/s/nimportequoi` → page « Signalement introuvable »
   avec bouton de téléchargement (404).
6. **EN** : app en anglais → message de partage en anglais.

## Cycle de vie + boucle du signaleur (2026-08-09)

Build v67+ (staging). Re-seeder avant la recette (les seeds > 48 h expirent).

1. **Tu n'es pas seul** : compte A signale ; compte B (connecté) confirme →
   A reçoit « Tu n'es pas seul 🤝 — Un voisin confirme ta coupure à … ».
   (Rejoué à la 5e confirmation, jamais entre les deux.)
2. **Promesse du retour** : le formulaire de signalement affiche la ligne
   « En signalant, tu seras prévenu dès que le service revient… » (🔔 ambre).
3. **Ping « Toujours coupé ? »** (simuler : vieillir un report de 4 h ou
   abaisser PING_AFTER_MS sur staging) : auteur + confirmeurs reçoivent la
   notif avec [Toujours coupé] [C'est revenu ✓] — UNE seule fois par
   personne, jamais entre 21 h et 7 h (heure CM).
4. **[Toujours coupé]** → la tache de la carte redevient vive (updatedAt
   rafraîchi) sans ouvrir l'app ; aucun compteur ne bouge.
5. **[C'est revenu ✓]** → vote de rétablissement compté ; au seuil,
   auto-résolution + notifs de retour.
6. **Ligne d'impact** : la notif de rétablissement des confirmeurs contient
   « Ta confirmation a aidé à alerter N voisins » quand N > 0.
7. **Expiration** : un report sans AUCUNE activité depuis 48 h disparaît
   (archivé avec autoExpiredAt) SANS notification ; jamais compté « résolu ».
