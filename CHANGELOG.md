# Changelog

Toutes les évolutions notables de NJUKA. Format inspiré de
[Keep a Changelog](https://keepachangelog.com/fr/). Versionnage : `X.Y.Z+build`.

## [Non publié]

### Ajouté
- **Onboarding : slide « Active ta localisation »** : explique que les alertes de
  proximité dépendent de la localisation (« sans localisation, tu peux signaler,
  mais tu ne recevras pas ces alertes ») — contre l'échec silencieux « j'ai
  refusé le GPS et je ne reçois rien sans comprendre pourquoi ».
- **Onboarding : slide « Crée un compte »** : rappelle que tout est faisable en
  anonyme, puis liste les 4 avantages réels d'un compte (suivre son quartier pour
  les coupures programmées, garder son historique en changeant de téléphone, ses
  statistiques, son pseudo sur ses signalements).
- **Bandeau « Localisation désactivée »** (accueil + carte) : quand la
  localisation n'est pas accordée, un bandeau prévient que les alertes de
  proximité ne fonctionneront pas, avec un bouton **Activer** (déclenche le
  pop-up système, ou ouvre les réglages si refus définitif ; backfill de la
  position si accordée). Se masque dès que l'accès est accordé.
  (`lib/widgets/location_alerts_banner.dart` + `requestLocationForAlerts`.)

### Modifié
- **Onboarding : slide « Alertes à proximité » corrigée** (texte périmé). Avant :
  « Avec un compte … quand une coupure est *confirmée* ». Après : « dès qu'une
  coupure est *signalée* près de chez toi — *sans créer de compte* » (reflète la
  notif à la création + l'ouverture aux anonymes de la 1.4.1). FR + EN.
- **Feuille de permission localisation (priming) corrigée et enrichie.** Elle ne
  parlait que du signalement, et affirmait « utilisée uniquement pour le
  signalement » — **faux** depuis que la position sert aussi au ciblage des
  alertes. Reformulée : situe tes signalements **+ te prévient des coupures près
  de chez toi** ; mention « jamais partagée à des tiers » conservée. FR + EN.
- **R8 / minification RÉACTIVÉE pour les builds release** (`isMinifyEnabled` +
  `isShrinkResources = true`), avec des règles `keep` dédiées dans
  `android/app/proguard-rules.pro` (attributs Crashlytics, Play Core/deferred
  components, énumérations, `@Keep`, neutralisation des warnings Firebase/GMS
  optionnels). Lève la recommandation Play « optimisation DEX / obscurcissement »
  (échéance fév. 2027). Désactivée depuis juin 2026 car R8 élaguait
  l'enregistrement réflexif d'un plugin Firebase (NPE au démarrage release) ;
  les règles corrigent ce point. **Validé sur appareil** (Samsung R5CW20FHA4P,
  build staging release) : démarrage, auth anonyme, stream Firestore, carte
  (geolocator + flutter_map) — aucun crash ni exception. `mapping.txt` généré
  (déobfuscation Crashlytics/Play automatique au build release).

### Corrigé
- **Notifs de proximité : destinataire passif injoignable (position device manquante).**
  Un device était enregistré **sans position** quand la localisation n'était pas
  encore accordée au démarrage (`registerForUser`) — et la position n'était
  backfillée qu'à la **création d'un signalement** ou au **pull-to-refresh**. Un
  destinataire anonyme qui ne fait qu'ouvrir l'app pour *recevoir* restait donc
  **hors du rayon 500 m** de `onReportCreated` → aucune notif. La position du
  device est désormais aussi backfillée à l'**ouverture de la carte**
  (`myPosition`) et à l'**activation du filtre « À proximité »** (`setNearOnly`),
  via `refreshGeohashFrom` (idempotent, skip même cellule). `onReportCreated` et
  l'enregistrement anonyme (volet C) fonctionnaient déjà en prod — c'était bien
  la **couverture de position** qui manquait pour les destinataires passifs.
- **Carte : plus de « flash Cameroun » à l'ouverture.** La carte s'ouvrait sur
  la position par défaut (Yaoundé) avant de sauter sur la position réelle du
  téléphone. On lit désormais la **dernière position connue** (cache système,
  instantané, sans permission ni fix GPS) pour cadrer la carte immédiatement sur
  l'utilisateur, derrière un voile de chargement qui masque le centrage initial.
  Le fix GPS précis affine ensuite en arrière-plan. (`lastKnownPosition` ajouté
  à `LocationRepository` / `LocationService` / `ReportProvider` ; logique de
  voile dans `map_screen.dart`.) iOS ne persistant pas de dernière position, le
  repli y reste le fix précis — sans régression.

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
