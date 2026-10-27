# Plan — Corriger les notifications de proximité (notifier à la création)

## ✅ FAIT (2026-10-27) — A, B, C, E, F implémentés et vérifiés
- A : `onReportCreated` ajoutée (notif à la création, amorce épicentre + notifiedUserIds).
- B : `onConfirmationCreated` refactorée (report + boucle signaleur AVANT le garde position ;
  plus d'abandon total sans GPS).
- C : règles `devices` ouvertes aux anonymes + `AuthProvider` enregistre le device pour les
  sessions anonymes. Test de règles mis à jour.
- E : `onRestorationCreated` notifie l'auteur + confirmeurs « retour signalé » quand le seuil
  n'est pas atteint (dédup `returnNotifiedUserIds`) ; sinon résolution → `onReportResolved`.
- F : fonctions pures (`returnNotifRecipients`, `restorationReportedContent`) testées.
- Vérifs : functions `tsc` + 81 tests OK ; règles 51 tests OK ; `flutter analyze` propre.
- RESTE : **G — déployer staging + smoke test sur device réel, puis prod.**

---


Décision (2026-10-27) : **notifier le voisinage dès la CRÉATION d'un signalement**
(on ne peut pas garantir qu'une 1re personne ouvrira l'app pour confirmer).
Abandon de l'exigence « confirmation d'abord » comme condition d'envoi.

## Constat (diagnostic)
- Aucune notif n'est envoyée aujourd'hui : `notifiedUserIds = 0` sur tous les reports prod.
- Cause : le système est *piloté par les confirmations* + `onConfirmationCreated` abandonne
  si le confirmeur n'a pas de position + les anonymes n'ont pas de device FCM.
- Prérequis OK : le report porte déjà `position` + `geohash` à la création (`toCreateMap`).

## A — Backend : NOUVELLE fonction `onReportCreated` (functions/src/index.ts)
Déclencheur `onDocumentCreated("reports/{reportId}")`.
1. Lire le report. Si `archivedAt` ou pas de `position` → log + return.
2. `devicesWithinRadius(report.position, NOTIFY_RADIUS_M)` (réutilise le helper existant).
3. Filtrer : `fcmEnabled !== false`, exclure `report.userId` (l'auteur).
4. Écrire sur le report (dédup pour la suite) :
   - `notificationEpicenters = arrayUnion(report.position)`
   - `notifiedUserIds = arrayUnion(...nouveauxUserIds)`
5. `sendOutageNotif(tokens, reportId, report)` — message data-only « Coupure à proximité »
   AVEC boutons de vote (identique à l'existant).
6. Config : 256MiB, région par défaut, `retryCount:0`.

## B — Backend : AJUSTER `onConfirmationCreated`
Devient l'**extension** de la vague (tache d'huile) + boucle du signaleur, robuste sans GPS.
1. **Déplacer la boucle du signaleur** (`shouldNotifyAuthor` → « tu n'es pas seul ») AVANT
   le garde `if (!cp)` : elle doit se déclencher même si le confirmeur n'a pas de position.
2. Si `cp` absente → faire la boucle signaleur puis `return` (plus d'abandon total ;
   la zone de base est déjà couverte par `onReportCreated`).
3. Garder l'update du rayon d'impact (carte) + l'extension d'épicentres **uniquement si `cp`**.
4. Dédup inchangée : `notifiedUserIds` / épicentres sont désormais amorcés dès la création,
   donc pas de re-notification des mêmes personnes.

## C — Limite majeure à TRANCHER : atteindre les anonymes
« Tout le monde » = aujourd'hui seulement les **comptes** (les anonymes n'ont pas de device FCM,
règle `!isAnonymous()` + `registerForUser` ignoré pour les anonymes).
Pour vraiment toucher tout le monde, il faut l'un de :
- **An1** : autoriser l'enregistrement d'un `devices` pour les anonymes
  (assouplir `firestore.rules` devices create/update + `AuthProvider`/`NotificationService`
  enregistrent le token pour les sessions anonymes). ⚠️ revoir les invariants (profil, pseudo
  restent interdits aux anonymes ; seul le device/token s'ouvre).
- **An2** : topics FCM par geohash (abonnement à une zone). Architecture plus lourde.
→ Sans ce chantier, le fix A+B fiabilise l'envoi mais ne touche QUE les comptes.

## D — Garde-fous anti-spam (recommandé, car on notifie avant validation)
- Les boutons « Pas chez moi » (denials) permettent de filtrer les faux positifs — déjà en place.
- Optionnel (phase 2) : ne pas re-notifier un quartier si un report ONGOING du même service
  existe déjà à < X m depuis < Y min (éviter double notif pour la même coupure).

## E — Rétablissement (« le courant est revenu ») — décision séparée
Aujourd'hui la notif ne part qu'à la résolution (seuil ≥3 votes ou moitié des confirmations) →
ne se déclenche jamais avec peu d'utilisateurs. Options :
- **R1** : à chaque `restorations/{uid}` créé, notifier l'auteur + confirmeurs « quelqu'un
  signale le retour » (signal doux), sans attendre le seuil.
- **R2** : abaisser le seuil de résolution (ex. min 1–2) → `onReportResolved` se déclenche.
→ Hors périmètre « notifier à la création » mais à décider en parallèle.

## F — Tests (avant déploiement)
- `onReportCreated` : report avec position + devices proches → envoie, exclut l'auteur,
  écrit `notifiedUserIds`/épicentre ; report sans position → rien.
- `onConfirmationCreated` : confirmation SANS position → boucle signaleur OK, pas d'abandon
  avant, pas de re-notif de la zone de base.

## G — Déploiement
1. `npm run build` (functions) + `npm test`.
2. Déployer STAGING, smoke-test : créer un report sur staging, vérifier la notif sur un device réel.
3. Déployer PROD.
4. Pas de nouvel index Firestore (requête geohash devices réutilisée).

## Ordre conseillé
A + B + F (cœur du fix, peu risqué) → déployer/tester → puis décider C (anonymes) et E (rétablissement).
