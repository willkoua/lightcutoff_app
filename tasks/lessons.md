# Leçons — NJUKA

Format : `[date] | ce qui a mal tourné | règle pour l'éviter`

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

- **2026-06-10 | `tsx`/esbuild casse si on force une autre version de Node via nvm**
  `npm test` (tsx --test) sous un Node basculé via `export PATH=…/nvm/…` peut échouer avec une
  `TransformError` esbuild (« supportedArchitectures » / binaire incompatible) — faux positif.
  → **Règle** : lancer les tests sous le **Node par défaut** du shell ; ne forcer une version que
  pour les commandes qui l'exigent réellement.
