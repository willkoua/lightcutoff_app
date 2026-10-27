# Changelog

Toutes les évolutions notables de NJUKA. Format inspiré de
[Keep a Changelog](https://keepachangelog.com/fr/). Versionnage : `X.Y.Z+build`.

## [1.4.1+72] — 2026-10-27

Refonte des notifications de proximité pour qu'elles partent enfin de façon
fiable, + compatibilité Android 15.

### Ajouté
- **Notif de proximité dès la CRÉATION d'un signalement** (`onReportCreated`,
  Cloud Function) : les comptes à ≤ 500 m du lieu signalé sont alertés
  immédiatement, sans attendre une 1ʳᵉ confirmation (qui pouvait ne jamais
  venir). Amorce `notificationEpicenters` + `notifiedUserIds` pour la dédup.
- **Notifications pour les utilisateurs anonymes** : l'enregistrement d'un
  device FCM est désormais autorisé aux sessions anonymes (règle Firestore
  `devices` + `AuthProvider.registerForUser`). Avant, les anonymes ne pouvaient
  rien recevoir. Profil / pseudo / quartiers suivis restent réservés aux
  comptes.
- **Notif « retour signalé »** (`onRestorationCreated`, volet E) : quand un
  voisin déclare le retour mais que le seuil de résolution n'est pas atteint,
  l'auteur + les confirmeurs reçoivent « Le courant/l'eau est peut-être
  revenu ». Dédup via `returnNotifiedUserIds` (une fois max par personne).
- **Affichage bord à bord** (Android 15 / `targetSdk 36`) :
  `SystemUiMode.edgeToEdge` + barres système transparentes (`main.dart`).

### Modifié
- `onConfirmationCreated` réordonnée et robustifiée : le report et la boucle du
  signaleur (« tu n'es pas seul » à la 1ʳᵉ/5ᵉ confirmation) s'exécutent **avant**
  le test de position. Une confirmation sans GPS n'abandonne plus tout — elle
  n'étend simplement pas la vague (zone de base déjà couverte à la création).

### Tests
- Fonctions pures `returnNotifRecipients` + `restorationReportedContent`
  couvertes (functions : 81 tests). Test de règles mis à jour : un anonyme PEUT
  enregistrer son propre device (rules : 51 tests). `flutter analyze` propre.
- Smoke test staging bout en bout : `onReportCreated` → notif « Coupure à
  proximité » reçue sur un device **anonyme** (volets A + C validés en réel).

### Déploiement
- Backend prod : `onReportCreated` (nouvelle), `onConfirmationCreated` +
  `onRestorationCreated` (mises à jour), règles Firestore.
- iOS 1.4.1 (72) uploadé sur App Store Connect ; Android AAB 72 pour Play.
- Outil : `functions/scripts/smokeNotif.cjs` pour tester les notifs de proximité.

### Notes
- dSYM Firebase non inclus à l'upload iOS (warnings non bloquants ; impacte
  seulement la symbolication fine des crashs).
- Détail complet du plan : `tasks/PLAN-NOTIFICATIONS.md`.

## [1.4.0+71] — 2026-10

- Coupures programmées **Kenya** : KPLC (électricité) + Nairobi Water (eau),
  ingestion quotidienne, `serviceType` sur les coupures officielles.
- Refonte de l'onglet « Programmées » : filtre région → ville → date + recherche,
  carte « zone d'impact », ajout à l'agenda, partage avec image générée.
- Conformité Play : lien source officielle + disclaimer d'indépendance.
- (Build 71 : rebuild après consommation du versionCode 70 par une soumission
  Play rejetée ; iOS resté en build 70.)
