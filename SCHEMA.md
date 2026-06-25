# Schéma de données — NJUKA

Modèle Firestore du projet (backend `lightcutoff-dev`). Source de vérité pour les
collections, champs et règles de sécurité. Les modèles Dart correspondants sont
dans `lib/models/`.

Légende : ✅ MVP · 🔵 post-MVP

---

## Collection `users/{uid}`

> L'id du document = l'`uid` Firebase Auth.

| Champ | Type | MVP | Description |
|-------|------|-----|-------------|
| `email` | string | ✅ | email de connexion / récupération |
| `username` | string | ✅ | pseudo unique (minuscules) — connexion par pseudo |
| `firstName` | string | ✅ | prénom |
| `lastName` | string | ✅ | nom |
| `birthDate` | timestamp \| null | ✅ | date de naissance |
| `phoneNumber` | string \| null | ✅ | contact / contexte coupure |
| `photoURL` | string \| null | ✅ | avatar (URL Firebase Storage) |
| `homeLocation` | map `GeoArea` | ✅ | quartier de résidence (ciblage notifs) |
| `role` | string enum | ✅ | `citizen` \| `operator` \| `admin` |
| `status` | string enum | ✅ | `active` \| `disabled` |
| `disabledAt` | timestamp \| null | ✅ | date de désactivation du compte |
| `createdAt` | timestamp | ✅ | création (serveur) |
| `updatedAt` | timestamp | ✅ | dernière modification (serveur) |

Modèle Dart : `lib/models/app_user.dart`

---

## Collection `usernames/{username}`

Index pseudo → compte, pour la **connexion par pseudo** (résolution
pseudo→email avant authentification). Id du doc = pseudo en minuscules.

| Champ | Type | Description |
|-------|------|-------------|
| `uid` | string | propriétaire du pseudo |
| `email` | string | email du compte (résolution login pseudo→email) |

Règles : `get` public (résolution pré-auth), **pas de `list`** (anti-énumération),
écriture réservée au propriétaire (`uid == auth.uid`).

---

## Collection `reports/{id}`

Un document = une coupure dans une zone. Les signalements en double sont gérés
par **confirmations** (voir sous-collection), pas par création de nouveaux docs.

| Champ | Type | MVP | Description |
|-------|------|-----|-------------|
| `userId` | string | ✅ | auteur du signalement (uid Firebase Auth — **y compris anonyme** depuis le pivot 2026-06-24) |
| `authorUsername` | string \| null | ✅ | pseudo de l'auteur, dénormalisé à la création (attribution publique `@pseudo`) ; immuable. Prénom/nom restent privés. **`null` pour un report anonyme** — l'UI ne montre aucune référence à l'auteur. |
| `status` | string enum | ✅ | `ongoing` \| `resolved` |
| `type` | string enum | ✅ | `unplanned` (imprévue) \| `scheduled` (programmée). Tout signalement citoyen est `unplanned` ; les coupures `scheduled` sont alimentées par les opérateurs. |
| `serviceType` | string enum | ✅ | `electricity` (défaut) \| `water`. Introduit avec le pivot multi-service 2026-06-24. **Rétro-compat** : un report sans le champ est lu comme `electricity` (`ServiceType.fromName(null)`) — aucun backfill nécessaire. Pose la grille de lecture des filtres liste/carte/stats + couleur du chip et du marqueur (ambre = élec, sky = eau ; vert = résolu commun). |
| `position` | map `{lat, lng}` | ✅ | coordonnées GPS |
| `location` | map `GeoArea` | ✅ | zone lisible (reverse-géocodage) |
| `description` | string \| null | ✅ | texte libre |
| `mediaUrl` | string \| null | ✅ | média joint (GIF/JPEG/PNG) sur Firebase Storage ; images fixes redimensionnées à ≤ 1280 px |
| `geohash` | string \| null | ✅ | geohash de `position` (index de proximité ; `AppConstants.geohashPrecision`) |
| `confirmationCount` | int | ✅ | nb de confirmations (dénormalisé) |
| `restorationCount` | int | ✅ | nb de déclarations « courant revenu » (dénormalisé) ; quand le seuil est franchi, la Cloud Function `onRestorationCreated` passe le `status` à `resolved`. |
| `photoUrls` | string[] | 🔵 | preuves visuelles (Firebase Storage) |
| `reportedAt` | timestamp | ✅ | début de coupure signalé |
| `resolvedAt` | timestamp \| null | ✅ | retour du courant |
| `archivedAt` | timestamp \| null | ✅ | horodatage de suppression par l'auteur (soft-delete). Quand non-null : invisible côté app. Hard-delete (récursif) après 30 j via le cron `purgeArchivedReports`. |
| `createdAt` | timestamp | ✅ | création (serveur) |
| `updatedAt` | timestamp | ✅ | dernière modification (serveur) |

Modèle Dart : `lib/models/report.dart`

### Sous-collection `reports/{id}/confirmations/{uid}`

> L'id du document = l'`uid` du confirmant → **un seul vote par utilisateur**.

| Champ | Type | Description |
|-------|------|-------------|
| `createdAt` | timestamp | date de la confirmation |

Modèle Dart : `lib/models/confirmation.dart`

**Logique de confirmation** : à la création d'une confirmation, le client
incrémente `confirmationCount` du report parent dans une transaction. Les règles
autorisent un non-auteur à modifier uniquement les compteurs
(`confirmationCount`, `restorationCount`, `updatedAt`).

### Sous-collection `reports/{id}/restorations/{uid}`

> Symétrique aux confirmations. L'id du document = l'`uid` qui déclare que le
> courant est revenu chez lui → **un seul vote par utilisateur**.

| Champ | Type | Description |
|-------|------|-------------|
| `createdAt` | timestamp | date de la déclaration de rétablissement |

Modèle Dart : `lib/models/restoration.dart`

**Logique de résolution crowd-sourcée** : à la création d'une restoration, le
client incrémente `restorationCount`. La Cloud Function `onRestorationCreated`
(`functions/src/index.ts`) bascule alors le `status` en `resolved` quand le
seuil est franchi : `max(restorationMinVotes, ceil(confirmationCount × restorationRatio))`
(constantes dans `AppConstants`). **L'auteur du report peut déclarer son propre
rétablissement** (contrairement aux confirmations) — il devient un confirmant
parmi d'autres pour cette action.

---

## Collection `devices/{token}` 🟡 (notifications push — en cours)

**L'id du document est le token FCM** (un appareil = un token = un doc → upsert
idempotent). Le token n'est donc pas dupliqué en champ.

| Champ | Type | Description |
|-------|------|-------------|
| `userId` | string | propriétaire |
| `platform` | string enum | `android` \| `ios` |
| `homeLocation` | map `GeoArea` | zone de résidence (ciblage proximité v1) |
| `geohash` | string \| null | geohash de la zone (ciblage par rayon v2) |
| `fcmEnabled` | bool | l'utilisateur peut couper les alertes sans se désinscrire |
| `updatedAt` | timestamp | nettoyage des tokens périmés |

Modèle Dart : `lib/models/device.dart`

---

## Types partagés

### `GeoArea` (map) — `lib/models/geo.dart`
`{ country, region, city, neighborhood }` — découpage administratif lisible.

### `GeoPosition` (map) — `lib/models/geo.dart`
`{ lat, lng }` — coordonnées GPS précises.

---

## Règles de sécurité (`firestore.rules`)

Helper introduit avec le pivot anonyme (2026-06-24) :

```
function isAnonymous() {
  return isSignedIn()
    && request.auth.token.firebase.sign_in_provider == 'anonymous';
}
```

- **users** : lecture par propriétaire ou admin ; un utilisateur ne crée/modifie que son propre doc ; pas de suppression. **`!isAnonymous()`** sur create/update → un anonyme ne peut PAS avoir de profil tant qu'il n'a pas upgradé via `linkWithCredential` (le `sign_in_provider` passe alors à `password`/`google.com`).
- **usernames** : `get` public (résolution pseudo→email pré-auth) ; `list` interdit (anti-énumération) ; create/update réservé au propriétaire **et non-anonyme**.
- **reports** : lecture si connecté (y compris anonyme) ; création réservée à l'auteur ; un tiers ne peut faire que **+1** sur un compteur (`bumpsCounterByOne`) **et** uniquement en déposant son propre vote dans le **même commit atomique** (`castsVote`). L'auteur ne peut pas confirmer sa propre coupure (mais peut déclarer son rétablissement).
- **reports/{id}/confirmations** : lecture par auteur du report / admin / propriétaire de sa propre confirmation ; create par soi-même uniquement et **pas sur sa propre coupure**.
- **reports/{id}/restorations** : symétrique aux confirmations, lecture limitée comme confirmations. Create par soi-même uniquement, **y compris l'auteur du report**.
- **devices** : un utilisateur ne lit/écrit/supprime que ses propres appareils ET **non-anonyme** (pas de ciblage notifs sans homeLocation). La Cloud Function d'envoi utilise l'Admin SDK pour lire tous les devices et purger les tokens périmés.
- **official_outages** : lecture si connecté ; **écriture client interdite** (alimenté par la Cloud Function d'ingestion Eneo via Admin SDK).

---

## Décisions de conception

- **Modèle « 1 coupure par zone » + confirmations** plutôt que signalements indépendants → évite les doublons, donne de la crédibilité.
- **Audit** (`createdAt`/`updatedAt`) sur toutes les entités ; **désactivation de compte** via `status`/`disabledAt` sur `users`.
- **Photos reportées** après le MVP (nécessite Firebase Storage) — champ `photoUrls` documenté mais non implémenté pour l'instant.
- **Soft-delete des reports** via `archivedAt` : l'auteur peut retirer son signalement (disparaît immédiatement de l'app). Hard-delete récursif (sous-collections incluses) automatique après 30 jours via le cron `purgeArchivedReports`. Préserve les confirmations/restorations pour audit pendant la fenêtre de rétention.
- **Identité publique = `@pseudo` uniquement.** Le prénom/nom vivent dans `users/{uid}` (lecture propriétaire/admin). Les signalements affichent `@pseudo` (champ `authorUsername` dénormalisé, immuable) ; les confirmations restent anonymes (« Vous »/« Un utilisateur »). Le pseudo étant immuable, la dénormalisation ne peut pas devenir incohérente. Pose les bases d'un futur fil social éphémère par coupure.
- **Suppression de compte (RGPD / exigence stores)** via la Cloud Function callable `deleteAccount` (`Profil → Paramètres → Compte`). Stratégie **« anonymisation »** : les signalements de l'utilisateur sont conservés mais vidés de toute donnée perso (`userId=""`, `authorUsername=null`, `mediaUrl=null`) — la coupure reste un repère communautaire ; **profil**, **index pseudo**, **devices**, **médias Storage** (`report_media/{uid}/`) et **compte Auth** sont supprimés. Le compte Auth est supprimé en dernier (pas de données orphelines en cas d'échec). Procédure publique : `https://lightcutoff-dev.web.app/account-deletion`.
- **Anonymous Auth « léger »** (pivot 2026-06-24) : `signInAnonymously` au 1ᵉʳ lancement → l'utilisateur peut signaler et voter sans inscription. Les fonctions sociales (profil, statistiques, suivi de quartier, notifs) sont gardées derrière un mur d'upgrade ; `linkWithCredential` préserve l'uid → l'historique anonyme reste attaché. Limite acceptée v1 : **réinstaller l'app = nouvel uid** (mitigée par App Check, à durcir avec un rate limit Cloud Function si besoin).
- **Multi-service** (`ServiceType { electricity, water }`, pivot 2026-06-24) : un même schéma de report sert les deux services. Filtre persistant (`SharedPreferences` côté client) Tout / Électricité / Eau commun à la liste, la carte et les stats. Modèle de fournisseurs unifié `Utility { id, service, country, label, … }` ([`lib/config/utilities.dart`](lib/config/utilities.dart)) couvre Eneo (CM, élec) + CAMWATER (CM, eau) ; **adaptateur d'ingestion CAMWATER non implémenté** (l'ingestion Eneo continue de poser `serviceType = electricity`).
