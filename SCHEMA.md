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
| `email` | string | ✅ | identifiant de connexion |
| `displayName` | string | ✅ | nom affiché |
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

## Collection `reports/{id}`

Un document = une coupure dans une zone. Les signalements en double sont gérés
par **confirmations** (voir sous-collection), pas par création de nouveaux docs.

| Champ | Type | MVP | Description |
|-------|------|-----|-------------|
| `userId` | string | ✅ | auteur du signalement |
| `status` | string enum | ✅ | `ongoing` \| `resolved` |
| `cause` | string enum | ✅ | `unknown` \| `unplanned` \| `scheduled` \| `incident` |
| `position` | map `{lat, lng}` | ✅ | coordonnées GPS |
| `location` | map `GeoArea` | ✅ | zone lisible (reverse-géocodage) |
| `description` | string \| null | ✅ | texte libre |
| `confirmationCount` | int | ✅ | nb de confirmations (dénormalisé) |
| `photoUrls` | string[] | 🔵 | preuves visuelles (Firebase Storage) |
| `reportedAt` | timestamp | ✅ | début de coupure signalé |
| `resolvedAt` | timestamp \| null | ✅ | retour du courant |
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
autorisent un non-auteur à modifier uniquement `confirmationCount` (+ `updatedAt`).

---

## Collection `devices/{id}` 🔵 (post-MVP — notifications push)

| Champ | Type | Description |
|-------|------|-------------|
| `userId` | string | propriétaire |
| `messagingToken` | string | token FCM |
| `platform` | string enum | `android` \| `ios` |
| `updatedAt` | timestamp | nettoyage des tokens périmés |

---

## Types partagés

### `GeoArea` (map) — `lib/models/geo.dart`
`{ country, region, city, neighborhood }` — découpage administratif lisible.

### `GeoPosition` (map) — `lib/models/geo.dart`
`{ lat, lng }` — coordonnées GPS précises.

---

## Règles de sécurité (`firestore.rules`)

- **users** : lecture si connecté ; un utilisateur ne crée/modifie que son propre doc ; pas de suppression.
- **reports** : lecture si connecté ; création réservée à l'auteur ; mise à jour/suppression par l'auteur, sauf `confirmationCount`/`updatedAt` modifiables par tout utilisateur connecté (confirmations).
- **reports/{id}/confirmations** : lecture si connecté ; création/suppression uniquement par l'utilisateur lui-même (`uid == documentId`).

---

## Décisions de conception

- **Modèle « 1 coupure par zone » + confirmations** plutôt que signalements indépendants → évite les doublons, donne de la crédibilité.
- **Audit** (`createdAt`/`updatedAt`) sur toutes les entités ; **désactivation de compte** via `status`/`disabledAt` sur `users`.
- **Photos reportées** après le MVP (nécessite Firebase Storage) — champ `photoUrls` documenté mais non implémenté pour l'instant.
- **Pas de soft-delete** sur les reports pour le moment.
