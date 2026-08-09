# VISION — Fil de coupure (discussion locale éphémère)

> **Statut : VISION / cadrage V2. Aucune ligne de code à écrire maintenant.**
> Document de réflexion produit + design technique. À implémenter *après* distribution
> (test interne débloqué) et premiers vrais utilisateurs — une salle de discussion à 0 user
> est un monologue.
> Créé le 2026-06-10.
> **Mise à jour 2026-08-10** : un **étage 1 sans texte libre** (« précisions structurées » :
> tags fermés agrégés, zéro modération, compatible anonymes) a été entièrement planifié
> puis **mis en réserve** — plan prêt à dérouler dans `tasks/todo.md` (reste à valider la
> liste des tags). Le présent document reste la vision de l'étage 2 (texte libre, comptes
> only, exigences UGC : signalement + blocage utilisateur).

---

## 1. Concept

Quand un utilisateur crée un signalement de coupure, une **discussion locale éphémère**
s'ouvre, attachée à cette coupure. Les personnes concernées y échangent : « toujours coupé ?»,
« la SNEL dit 3 h », photos du quartier, etc. **Le fil ne vit que le temps de la coupure** :
il se fige quand le courant revient, puis disparaît avec le signalement.

### Cadrage / nommage — important
**Ne pas l'appeler « réseau social ».** Ni pour les utilisateurs, ni surtout pour la review
des stores (un « réseau social » déclenche un scrutin légal maximal). C'est une **discussion
de quartier, le temps de la panne** : un fil **local**, **éphémère**, **attaché à un événement
utilitaire**. Le bon modèle mental = un canal d'info terrain temporaire, pas un Twitter.

### Pourquoi c'est cohérent avec NJUKA
NJUKA = **outil d'information utile** (« le service, l'information »). Le fil doit faire remonter
de l'**info terrain actionnable** (cause, ETA de retour, périmètre touché), pas du bavardage.
Conçu ainsi, il sert la mission ; conçu comme un chat ouvert, il la dilue.

---

## 2. Cycle de vie (naissance → mort)

| Phase | Déclencheur | État du fil |
|---|---|---|
| **Naît** | Création du signalement | Ouvert en écriture |
| **Vit** | Tant que `status == ongoing` (non résolu, non archivé) | Ouvert |
| **Grâce** | Courant revenu / auto-résolu | **Lecture seule** pendant 1–2 h |
| **Meurt** | Fin du délai de grâce → suit le cycle du report | Purgé avec le report (cron 30 j) |

**Décisions :**
- ❌ **Pas de suppression brutale** à la résolution → on **fige en lecture seule**, puis purge
  via le cron existant `purgeArchivedReports`. Réutilise l'infra, laisse un « voilà ce qui s'est
  passé ».
- ⚠️ **Piège auto-résolution** : le seuil de restauration peut résoudre le report *alors que
  certains sont encore coupés*. Le **délai de grâce** évite de couper la parole au pire moment.
- ⚠️ **Report périmé** : un report qui reste `ongoing` longtemps → salle fantôme. Prévoir une
  expiration douce (ex. fil en lecture seule après X h sans activité).

---

## 3. Qui peut participer ? (LE choix de design)

**Décision : porte d'entrée = avoir confirmé la coupure** (ou en être l'auteur).

> « Confirme que tu es touché pour rejoindre la discussion. »

Pourquoi c'est le meilleur choix parmi les trois options envisagées :

| Option | Engagement | Anti-troll | Verdict |
|---|---|---|---|
| Tout user connecté | Max | Faible | ❌ spam/trolls |
| Proximité geohash | Moyen | Bon | 🟡 friction GPS, exclut le coupé qui est au boulot |
| **Avoir confirmé** | Bon | **Fort** | 🟢 **retenu** |

Bénéfices de la porte « confirmation » :
- Réutilise la donnée existante (`reports/{id}/confirmations/{uid}`).
- Limite naturellement aux **gens réellement concernés** → anti-troll intrinsèque.
- **Renforce la boucle cœur** : pour parler, il faut contribuer → plus de confirmations →
  meilleure preuve sociale. Le social devient une **récompense de la contribution**.

---

## 4. Synergie avec l'existant (à exploiter)

L'**anti-doublon 500 m** (qui pousse à *confirmer* un report existant plutôt qu'en recréer un)
**concentre tout le monde dans UNE seule salle** au lieu de fragmenter la conversation. C'est
exactement ce qui rend une salle vivante. Les mécanismes existants se nourrissent l'un l'autre.

Briques déjà en place réutilisées par le fil :
- `@pseudo` dénormalisé immuable (`authorUsername`) → attribution sans exposer prénom/nom.
- Sous-collections par report (même pattern que `confirmations/`, `restorations/`).
- Vote unique par user (id doc = uid) → réutilisé pour les **signalements de message** (flags).
- Pipeline média Storage (resize ≤ 1280 px, plafond 8 Mo).
- Proximité geohash, FCM (3 états + nav), cron de purge 30 j.

---

## 5. Contenu & modération

### Contenu
- **Palier 1 : texte seul + réactions en 1 tap.** Pas de photos au début.
- **Palier 2 : photos** (gros risque — voir ci-dessous), différé.

### 🔴 MUR DUR — modération obligatoire pour publier
Apple **Guideline 1.2** (UGC) et l'équivalent Google **rejettent** toute app à contenu généré
par les utilisateurs sans :
1. **Signaler** un message (flag).
2. **Bloquer** un utilisateur.
3. **CGU tolérance zéro** sur le contenu offensant (EULA).
4. Capacité à **retirer** le contenu + **éjecter** l'utilisateur.

> L'éphémère **n'efface PAS** cette obligation tant que le contenu est en ligne.
> Ce n'est pas une option, c'est une **condition de publication**.

Mise en œuvre minimale :
- `flagCount` sur chaque message + **auto-masquage** au-delà de N signalements.
- L'**auteur du report** (propriétaire de la salle) et/ou un **admin** peut supprimer un message.
- Blocage utilisateur (au moins au niveau du fil).
- **Photos (palier 2)** : risque contenu illégal/NSFW + EXIF GPS (re-PII). Soit auto-modération
  (vision model / Firebase ML — coût + complexité), soit on reste texte-only longtemps.

---

## 6. Combattre la salle vide (cold-start)

L'éphémère **aggrave** le démarrage à froid : rien ne s'accumule, chaque salle repart de zéro.

- **Pré-remplir avec une timeline système** : « 12h03 signalé · 12h20 8 confirment ·
  13h45 courant revenu ». Même sans un seul message humain, la salle *vit*.
- **Réactions en 1 tap** plutôt qu'un champ texte vide : « Toujours coupé ✋ », « Revenu ✅ »,
  « Bougies 🕯️ ». Friction quasi nulle → bien plus de participation qu'un champ blanc.
- **Épingler les updates de l'auteur** en haut → l'info utile ne se noie pas dans le flux.

---

## 7. Modèle de données (esquisse)

```
reports/{id}/messages/{msgId}
   authorUid       : string
   authorUsername  : string   // dénormalisé immuable (même pattern que report)
   text            : string   // longueur max bornée
   mediaUrl        : string?  // palier 2 seulement
   createdAt       : timestamp
   flagCount       : int (défaut 0)
   hidden          : bool (défaut false)   // auto-masquage modération

reports/{id}/messages/{msgId}/flags/{uid}   // 1 signalement par user (anti double-flag)
   createdAt : timestamp
```

**Coût maîtrisé** : le listener du fil n'est actif **que quand l'utilisateur est dans la salle**
(pas un firehose global). Lectures bornées.

---

## 8. Règles Firestore (principes)

- **Créer un message** : autorisé si `isSignedIn()` ET (auteur du report **OU** a confirmé,
  via existence de `confirmations/{uid}`) ET report **non archivé / non résolu**.
- **Lecture** : même audience que l'écriture (participants).
- **Flag** : `flags/{uid}`, 1 par user (même pattern vote-unique que confirmations).
- **Suppression d'un message** : auteur du message **OU** auteur du report **OU** admin.
- **Auto-masquage** : `hidden` basculé par Cloud Function quand `flagCount` franchit le seuil
  (ne pas laisser le client écrire `hidden` arbitrairement — même leçon que le compteur).
- ⚠️ Comme pour `confirmationCount`, **ne pas se reposer sur `hasOnly()`** pour protéger une
  valeur : contrôler la valeur ou déporter en Cloud Function.

---

## 9. Notifications & re-engagement

- « Quelqu'un a posté dans une coupure que tu as confirmée » → réutilise FCM.
- **Throttle agressif** (fatigue de notif — même discipline que le push de proximité envisagé).
- ⚠️ **Android-only** pour l'instant : push iOS **gelé** (pas d'APNs, attente accès Apple Dev).

---

## 10. RGPD / vie privée

- Identité publique = **`@pseudo` uniquement** (modèle existant). Idéalement **pas de PII** dans
  les messages.
- **Strip EXIF** sur les photos (palier 2) — on redimensionne déjà, ajouter le nettoyage GPS.
- Étendre la Cloud Function **`deleteAccount`** : anonymiser/supprimer aussi les **messages** de
  l'utilisateur (sinon données orphelines).
- La **politique de confidentialité** doit couvrir l'UGC.
- 🟢 **L'éphémère est un argument privacy** : « ce qui se dit pendant la panne disparaît avec
  elle ».

---

## 11. Plan de livraison par paliers

> Ordre conçu pour livrer de la valeur tôt, avec un risque croissant maîtrisé.

- **Palier 0 — Timeline système (faible risque, utile même solo)**
  Afficher dans le détail du report une chronologie : signalé / confirmations / résolu.
  Aucun UGC → aucune modération requise. Valide l'appétit pour « le détail vivant ».

- **Palier 1 — Réactions en 1 tap**
  Chips « Toujours coupé / Revenu / Bougies ». Agrégats anonymes. Pas de texte libre →
  toujours pas d'obligation de modération lourde.

- **Palier 2 — Texte libre (UGC) → DÉCLENCHE la modération obligatoire**
  Fil de messages texte, gating par confirmation, flag + blocage + suppression + CGU.
  **Ne pas livrer sans l'outillage de modération complet** (sinon rejet store).

- **Palier 3 — Photos**
  Le plus risqué. Strip EXIF + modération du contenu visuel. À évaluer seulement si les
  paliers précédents montrent un vrai usage.

---

## 12. Risques & décisions ouvertes

- 🔴 **Modération** = le risque opérationnel/légal nº1. Petite équipe + UGC = piège classique.
  L'éphémère atténue (le contenu s'auto-détruit) mais ne supprime pas la responsabilité.
- 🔴 **Timing** : feature la plus lourde du projet, sur une app à 0 user non distribuée.
  À cadrer maintenant, à coder **après** users + distribution.
- 🟡 **Mission** : risque de dérive « social pour le social ». Garde-fou : structurer pour
  l'info terrain (statut, ETA, périmètre), pas le bavardage.
- ❓ **Ouvert** : durée exacte du délai de grâce après résolution ?
- ❓ **Ouvert** : modération photos — auto (ML, coût) vs rester texte-only longtemps ?
- ❓ **Ouvert** : faut-il une notion d'admin/modérateur avant d'avoir une équipe ?

---

## 13. Ce que ça réutilise vs ce que ça ajoute

**Réutilise (existant)** : `@pseudo` dénormalisé · sous-collections par report · vote-unique
par user · média Storage · geohash · FCM · cron purge 30 j · CF `deleteAccount`.

**Ajoute (nouveau)** : sous-collection `messages/` + `flags/` · règles associées · UI fil +
réactions + timeline · outillage modération (flag/block/delete/CGU) · CF d'auto-masquage ·
extension de `deleteAccount` aux messages · throttling notif fil · (palier 3) strip EXIF.
