# Leçons — NJUKA

Format : `[date] | ce qui a mal tourné | règle pour l'éviter`

- **2026-07-26 | Purger les comptes Auth côté serveur laisse l'app installée avec des
  identifiants zombis** : au refresh du jeton (~1 h), le refresh token du compte
  supprimé est refusé → l'app devient silencieusement NON authentifiée →
  `PERMISSION_DENIED` sur tout (la liste se fige sur l'erreur, la carte affiche le
  **cache** → symptôme trompeur « visible sur la carte mais pas la liste »).
  → **Règles** : ① après toute purge de comptes serveur, TOUJOURS `adb shell pm
  clear` sur l'appareil de test ; ② résilience ajoutée : toute session vivante
  réarme l'auto-reconnexion anonyme (`_anonymousSignInAttempted = false` quand
  `user != null`) — une session tuée côté serveur retombe sur une session anonyme
  neuve au lieu de rester bloquée ; ③ pour diagnostiquer « données visibles carte
  mais pas liste » : logcat `PERMISSION_DENIED` d'abord, le cache Firestore masque
  les pannes d'auth.

- **2026-07-25 | Firebase marque les emails Facebook (et Apple masqué) comme NON
  vérifiés** → l'aiguillage `!user.emailVerified → écran « Vérifie ton email »`
  envoyait les connexions Facebook sur un écran absurde (avec bouton « renvoyer »
  qui envoie un vrai mail de vérification). Découvert au smoke-test prod.
  → **Règle** : la vérification d'email ne s'applique QU'AU provider `password`
  (`user.providerData.any(p => p.providerId == 'password')`). Les providers
  sociaux sont réputés vérifiés par leur fournisseur, quel que soit le flag.
  Corollaire mocktail : tout mock de `User` doit stubber `providerData`.

- **2026-07-23 | Premier build iOS = cascade de mises à niveau de la chaîne** (résolue en
  ~10 itérations) : ① SDK Firebase récents → **iOS 15 min** (Podfile + pbxproj) ;
  ② `flutter_facebook_auth 7.1.6` = **release cassée** (podspec épinglé FBSDK 18.0.2
  mais Swift incompatible — et le pin 17.x en Podfile conflicte avec le podspec) ;
  ③ `cloud_firestore 6.4.1` ne compile pas sur iOS (fix : 6.7.x — débloquer TOUTE la
  famille firebase ensemble, `pub upgrade` ciblé sur 1 paquet ne résout pas) ;
  ④ **Xcode 16.2 sur macOS 26 = incompatible** (AssetCatalogSimulatorAgent spawn fail,
  même après reboot) → Xcode 26 obligatoire (aussi exigé par l'App Store 2026) ;
  ⑤ après MAJ Xcode : restes de l'ancien dans `/Library/Developer` → `sudo xcodebuild
  -runFirstLaunch` ; ⑥ nouveau platform pack à retélécharger (`xcodebuild
  -downloadPlatform iOS`) ; ⑦ `fake_cloud_firestore` 4.2 exige Dart 3.8 → **MAJ
  Flutter 3.27→3.44** (qui débloque aussi facebook 7.2.0, corrigé des deux côtés).
  → **Règles** : sur un premier build iOS, s'attendre à mettre à niveau la chaîne
  ENTIÈRE (target iOS, Xcode, platform packs, Flutter, plugins) — itérer erreur par
  erreur SANS empiler les contournements, et retirer chaque pin temporaire dès que la
  vraie version corrigée est accessible. Ne jamais laisser vieillir Xcode ~2 ans
  derrière macOS. Après toute MAJ d'Xcode : `-runFirstLaunch` + platform pack.
  ⚠️ Suivi : Facebook 7.1.1→7.2.0 = **re-smoke-tester la connexion Facebook sur
  Android** (tél) avant le prochain déploiement testeurs.

- **2026-07-07 | Nettoyage protégé par règles exécuté APRÈS la perte des droits** :
  la suppression du doc `devices/{token}` à la déconnexion partait via le listener
  (`_onAuthStateChanged(null)`), donc APRÈS `signOut()` → `request.auth` n'était
  plus le propriétaire → **delete rejeté en silence** (catch muet) → le téléphone
  déconnecté continuait de recevoir les notifs du compte, et les votes-depuis-notif
  partaient sous l'uid anonyme. Détecté en croisant uid du vote (anonyme 2HhCE…) ≠
  uid du device (compte 8QD0…).
  → **Règle** : toute écriture de nettoyage gardée par `isOwner(...)` doit être
  faite **AVANT** de perdre l'identité (unregister avant signOut). Et un `catch`
  silencieux sur une opération de sécurité = bug invisible ; logger au minimum.

- **2026-07-07 | Boutons d'action sur notifs FCM = message data-only obligatoire** :
  un message FCM avec bloc `notification` est affiché PAR LE SYSTÈME (aucun bouton
  possible) et le handler background n'est PAS appelé. Pour des actions il faut :
  message **data-only** (title/body dans `data`) + affichage via
  flutter_local_notifications (`AndroidNotificationAction`, `showsUserInterface:
  false` → callback top-level `@pragma('vm:entry-point')` dans un isolate dédié,
  ré-init Firebase dedans) + receiver `ActionBroadcastReceiver` dans le manifest +
  `getNotificationAppLaunchDetails()` pour le tap à froid (getInitialMessage ne
  couvre pas les notifs locales). ⚠️ Breaking : les anciennes versions d'app
  n'affichent RIEN pour un data-only en arrière-plan → forcer la mise à jour des
  testeurs.

- **2026-07-06 | Changer des chaînes l10n sans relancer les tests** : le passage au
  tutoiement (v48) a cassé 1 assertion de `l10n_helpers_test.dart` (« Vous devez
  être connecté. ») — détecté seulement à la session suivante car seul `flutter
  analyze` avait tourné (analyze ne voit pas les littéraux attendus des tests).
  → **Règle** : toute modif d'ARB / de copy = `flutter test` complet avant build,
  pas seulement analyze ; les tests assertent des littéraux de traduction.

- **2026-07-06 | Rayon de notif « à vol d'oiseau » ≠ emprise réelle d'une coupure** :
  notifier tout le monde dans 2 km à chaque signalement = énorme faux positif
  (topologie réseau ≠ distance) + fatigue de notifs. Refonte : notifs **pilotées
  par les confirmations** (rayon 500 m qui s'étend de proche en proche, dédup
  1 notif/user/report, distance exacte, garde-fou coût).
  → **Règle** : un rayon de proximité fin exige la **position exacte des
  destinataires**, pas juste un geohash (précision 6 ≈ 1,2 km trop grossier).
  Stocker `position` exacte sur `devices` **et** sur le vote de confirmation,
  **lecture verrouillée aux règles** (admin/owner) → la Cloud Function lit via
  Admin SDK sans exposer la position aux tiers. Pré-filtre geohash grossier
  (rayon élargi pour matcher la précision stockée) PUIS coupe `distanceBetween`.

- **2026-07-06 | Ne pas écraser en silence un choix de conception documenté** :
  le modèle `Confirmation` disait explicitement « jamais de lat/lng exact
  (anonymat) ». Ajouter la position exacte y touchait → signalé à l'utilisateur
  AVANT, options présentées, choix validé (position exacte + lecture admin-only,
  qui *renforce* l'anonymat en retirant l'accès de l'auteur du report).
  → **Règle** : un commentaire « on ne fait jamais X » = décision délibérée ;
  la contredire se discute avec l'utilisateur, ne se code pas en douce.

- **2026-07-06 | Cloisonnement pays « à l'affichage » ≠ « à la requête »** : la liste
  était filtrée par pays **côté client** (`filteredReports`), mais `watchReports`
  récupérait les **N récents du MONDE** (`orderBy reportedAt · limit`). À volume, un
  autre pays sature la fenêtre → un utilisateur **ne voit plus son propre pays**.
  → **Règle** : quand on borne une liste par un critère (pays, service…) **et** qu'on
  `limit`, appliquer le `where` **côté serveur** dans la même requête, sinon la
  `limit` porte sur le mauvais périmètre. Ici : `where('location.countryCode', ==)` +
  index composite `(location.countryCode ASC, reportedAt DESC)` dans
  `firestore.indexes.json` (déployé via `firebase deploy --only firestore:indexes`).
  Garder aussi le filtre client (couvre le chemin proximité `reportsWithinRadius`).
  Changer de pays doit **re-souscrire** le flux (la fenêtre `limit` est par pays).

- **2026-07-06 | mocktail : ajouter un param nommé casse les stubs existants** :
  ajouter `countryCode` à `watchReports` a fait échouer les `when(...limit: any...)`
  quand l'appel réel passait `countryCode: 'CM'` (→ retourne `null` au lieu du Stream).
  → **Règle** : après ajout d'un param nommé à une méthode mockée, étendre TOUS les
  matchers `any(named: ...)` au nouveau param (stubs **et** `verify`).

- **2026-06-05 | Signing Android — keystore PKCS12 + 2 mots de passe différents** :
  `keytool -genkeypair -storepass X -keypass Y` (X≠Y) crée un keystore **PKCS12**
  (format par défaut depuis Java 9) qui **n'autorise pas un mot de passe de clé
  distinct du mot de passe du store** — keytool **ignore silencieusement** le
  `-keypass` (juste un warning) et protège la clé avec le `storePassword`. Si
  `key.properties` met `keyPassword=Y`, Gradle échoue à la signature :
  *« Get Key failed: Given final block not properly padded »*.
  → **Règle** : pour un keystore PKCS12/Android, utiliser **le même mot de passe**
  pour le store et la clé (`storePassword == keyPassword`).

- **2026-06-05 | keytool localisé (FR) casse les `grep` d'empreinte** : la sortie
  affiche « SHA 256 » (avec espace) et non « SHA256:/SHA-256: ».
  → **Règle** : matcher `SHA.?256` (ou `SHA 256`) quand on parse `keytool -list`.

- **2026-06-10 | Émulateur firebase-tools + firebase-functions v7 : worker HTTPS plante**
  Toute invocation d'une fonction `onRequest`/HTTPS dans l'émulateur (firebase-tools 14.11.2 +
  firebase-functions v7.x) meurt avec « functions.config() has been removed in firebase-functions
  v7 » → « Your function was killed… unhandled error » → « Failed to load function ». Ce n'est
  **pas** le code (le module charge bien ; la prod GCF n'est pas concernée), c'est le shim du worker
  HTTPS de l'émulateur. `onRequest` n'attrape pas non plus les rejets async → l'erreur réelle est
  avalée.
  → **Règle** : pour tester une logique de fonction en émulateur, **l'appeler en direct via un
  script** (`firebase emulators:exec --only firestore "node script.cjs"`, qui injecte
  `FIRESTORE_EMULATOR_HOST`), plutôt que via un déclencheur HTTP. Ne pas perdre de temps à
  soupçonner le code applicatif sur ce message.

- **2026-06-13 | Firebase Functions v2 : retirer une variable de `.env` ne la SUPPRIME pas du déployé**
  Après avoir mis `RESTORATION_MIN_VOTES=1` via `functions/.env.lightcutoff-dev` puis **supprimé le
  fichier** et redéployé, la variable **persistait à 1** sur la fonction Cloud Run (vérifié dans les
  logs : `threshold=1` alors qu'on attendait 3). Firebase ne réconcilie/efface pas une env var
  absente du `.env` ; elle reste posée sur le service.
  → **Règle** : pour annuler un override d'env, **réécrire explicitement la valeur voulue** dans le
  `.env.<projet>` (ex. `RESTORATION_MIN_VOTES=3`) puis redéployer — ne pas se contenter de
  supprimer le fichier. Vérifier avec
  `gcloud functions describe <fn> --gen2 --region <r> --format="value(serviceConfig.environmentVariables)"`.

- **2026-06-20 | `FlutterError.onError = recordFlutterFatalError` = tout devient un crash FATAL**
  Câbler `FlutterError.onError` directement sur `crashlytics.recordFlutterFatalError` (et
  `PlatformDispatcher.onError` avec `fatal: true`) remonte **toute** erreur framework comme crash
  fatal — **y compris les échecs de chargement d'images** (`flutter_map` charge ses tuiles via
  `package:http` ; un `Connection reset by peer` sur `tile.openstreetmap.org` lève une
  `ClientException` rapportée via le flux d'image → `FlutterError.onError`). Résultat : faux crashs
  fatals en masse dans Crashlytics pour de simples pertes réseau transitoires.
  → **Règle** : filtrer les erreurs réseau transitoires (`SocketException`, `TimeoutException`,
  `HttpException`, `ClientException`) dans `FlutterError.onError`/`PlatformDispatcher.onError` et les
  enregistrer en **non-fatal** (`fatal: false`), pas comme crash. Voir `_isTransientNetworkError`
  dans `lib/main.dart`.
  → **Corollaire tuiles** : en staging on lance souvent **sans `STADIA_API_KEY`** → repli sur le
  serveur **OSM public** (`tile.openstreetmap.org`), qui *rate-limit*/reset les connexions (sa
  politique d'usage interdit l'usage applicatif lourd). Pour réduire la source : builds de
  test/prod avec `--dart-define=STADIA_API_KEY=…` (tuiles Stadia).

- **2026-06-10 | `tsx`/esbuild casse si on force une autre version de Node via nvm**
  `npm test` (tsx --test) sous un Node basculé via `export PATH=…/nvm/…` peut échouer avec une
  `TransformError` esbuild (« supportedArchitectures » / binaire incompatible) — faux positif.
  → **Règle** : lancer les tests sous le **Node par défaut** du shell ; ne forcer une version que
  pour les commandes qui l'exigent réellement.

- **2026-06-26 | Route poussée AU-DESSUS d'un gate réactif (AuthGate) → doit se pop elle-même au succès**
  `LoginScreen` se fiait au commentaire « l'AuthGate route automatiquement » : FAUX quand
  l'écran est **poussé** (`Navigator.push`) par-dessus l'AuthGate (depuis le mur d'upgrade /
  AnonymousRetry). L'auth réussissait, l'AuthGate basculait bien `anonymous → authenticated`
  **en dessous**, mais la route de login restait **devant** → l'utilisateur n'était pas redirigé
  (symptôme : « l'auth marche mais pas de redirection »). `UpgradeAccountScreen`, lui, faisait
  déjà `Navigator.pop()` au succès (d'où l'asymétrie trompeuse).
  → **Règle** : un écran d'auth **poussé** au-dessus d'un gate piloté par état doit **se retirer
  lui-même** (`Navigator.pop()` / `popUntil(isFirst)`) au succès. Le gate ne route automatiquement
  que pour les écrans qu'il **possède** comme racine (MainShell, EmailVerification, CompleteProfile,
  AnonymousRetry), pas pour les routes empilées par-dessus.

- **2026-06-26 | Déconnexion = flash de SplashScreen (re-anonyme transparent raté)**
  L'app étant anonyme-first, `logout()` réarme le flag anti-boucle pour re-créer une
  session anonyme. Mais `_onAuthStateChanged(null)` forçait `_status = AuthStatus.unknown`
  (→ SplashScreen) AVANT le `signInAnonymously()`. Au démarrage à froid c'est OK (le statut
  est déjà `unknown` par défaut), mais après un **logout** (où on était sur MainShell), forcer
  `unknown` fait **flasher le splash** le temps du round-trip réseau anonyme — alors que le
  commentaire promettait une transition « transparente ».
  → **Règle** : pour une re-auth de fond (logout → re-anonyme), **ne pas réinitialiser le statut
  vers l'écran de chargement plein écran**. Laisser le statut courant (MainShell) pendant l'appel
  async ; le défaut `unknown` suffit à couvrir le démarrage à froid. Distinguer « 1ère ouverture »
  (splash légitime) de « transition de session » (doit être invisible).
