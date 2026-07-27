/**
 * Cloud Functions NJUKA — notifications push FCM (Phase 4).
 *
 * Déclencheur : à chaque création d'un signalement (`reports/{id}`), on
 * notifie les devices dans un rayon de [NOTIFY_RADIUS_M] mètres.
 *
 * Stratégie de ciblage (en deux temps) :
 *   1. **Géohash** : si le report a une position et que des devices ont un
 *      `geohash`, on utilise `geofire-common.geohashQueryBounds` pour borner
 *      la collection (rapide, scalable).
 *   2. **Fallback ville** : pour les devices sans geohash (permission GPS
 *      refusée à l'enregistrement), on cible ceux dont `homeLocation.city`
 *      correspond à `report.location.city`.
 *
 * Exclusions systématiques : auteur du report + devices avec `fcmEnabled` faux.
 * Envoi par batches de 500 (limite FCM). Tokens `UNREGISTERED` / `INVALID`
 * supprimés silencieusement (nettoyage opportuniste — Phase 5 ajoutera un
 * cron de purge périodique).
 */

import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { geohashQueryBounds, distanceBetween } from "geofire-common";
import {
  buildBody,
  plannedAlertBody,
  resolutionThreshold,
  resolvedNotifContent,
  shouldResolve,
  effectiveMinVotes,
} from "./logic";
import { EneoAdapter } from "./sources/eneo";

admin.initializeApp();

/// Rayon de notification (mètres) autour d'un épicentre — la coupure se
/// propage de proche en proche à chaque confirmation (cf. onConfirmationCreated).
const NOTIFY_RADIUS_M = 500;
/// Pré-filtre geohash grossier : on interroge `devices` sur un rayon plus large
/// (les geohash devices sont en précision 6 ≈ 1,2 km, incompatibles avec des
/// bornes fines à 500 m) puis on coupe à la distance EXACTE via `device.position`.
const PREFILTER_RADIUS_M = 2000;
/// Garde-fou coût : une confirmation dont l'épicentre est à moins de cette
/// distance d'un point déjà couvert ne relance pas de notif (elle reste comptée).
const EPICENTER_MERGE_M = 100;
const BATCH_SIZE = 500;
const OUTAGE_CHANNEL_ID = "njuka_outage_alerts";
const STALE_DEVICE_AGE_DAYS = 90;
const ARCHIVED_RETENTION_DAYS = 30;

interface GeoPoint {
  lat: number;
  lng: number;
}

interface GeoArea {
  country?: string;
  region?: string;
  city?: string;
  neighborhood?: string;
}

interface ReportDoc {
  userId: string;
  position?: GeoPoint;
  location?: GeoArea;
  geohash?: string;
  type?: string;
  cause?: string; // anciens docs (avant le rename type)
  serviceType?: string; // electricity | water (absent = electricity, legacy)
  archivedAt?: FirebaseFirestore.Timestamp | null;
}

interface DeviceDoc {
  userId: string;
  platform?: string;
  homeLocation?: GeoArea;
  geohash?: string;
  position?: GeoPoint; // position exacte (lat/lng) — filtrage distance exacte
  fcmEnabled?: boolean;
}

interface ConfirmationDoc {
  position?: GeoPoint; // position exacte du confirmeur (règles : lecture admin/owner)
  geohash?: string;
}

interface ReportNotifState {
  notifiedUserIds?: string[]; // dédup : un user notifié au plus une fois / report
  notificationEpicenters?: GeoPoint[]; // points déjà couverts (garde-fou coût)
}

/**
 * Notifications de proximité **pilotées par les confirmations** (redesign
 * 2026-07-06). La création d'un signalement **ne notifie plus** personne (un
 * signalement isolé est un signal faible). Dès la **1ʳᵉ confirmation** (2ᵉ
 * témoin), on notifie les comptes dans un rayon serré (`NOTIFY_RADIUS_M`) qui
 * **s'étend de proche en proche** : chaque confirmation devient un nouvel
 * épicentre → la zone notifiée épouse l'emprise réelle de la coupure.
 *
 * Invariants :
 *  - **Dédup** : un utilisateur reçoit au plus UNE notif par signalement
 *    (`report.notifiedUserIds`).
 *  - **Distance exacte** : pré-filtre geohash grossier puis coupe à la distance
 *    réelle via `device.position` (les geohash devices sont trop grossiers).
 *  - **Garde-fou coût** : une confirmation trop proche d'un point déjà couvert
 *    ne relance pas de notif (mais reste comptée côté client).
 *  - Exclusions : auteur du signalement, confirmeur, `fcmEnabled=false`,
 *    anonymes (pas de doc `devices`).
 */
export const onConfirmationCreated = onDocumentCreated(
  "reports/{reportId}/confirmations/{confirmerId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const reportId = event.params.reportId as string;
    const confirmerId = event.params.confirmerId as string;
    const conf = snap.data() as ConfirmationDoc;

    const db = admin.firestore();

    // Position du confirmeur = épicentre de la vague. Si le vote n'en porte
    // pas (vote depuis le bouton de notification — GPS indisponible dans
    // l'isolate d'arrière-plan — ou vieille version d'app), on retombe sur la
    // **position enregistrée de son device** (rafraîchie à chaque ouverture).
    // On ne renonce à la notif que si on n'a vraiment rien.
    let cp = conf.position;
    if (!cp || typeof cp.lat !== "number" || typeof cp.lng !== "number") {
      cp = undefined;
      const devSnap = await db
        .collection("devices")
        .where("userId", "==", confirmerId)
        .limit(5)
        .get();
      for (const d of devSnap.docs) {
        const pos = (d.data() as DeviceDoc).position;
        if (pos && typeof pos.lat === "number" && typeof pos.lng === "number") {
          cp = pos;
          logger.info("Vote sans position → repli sur la position du device.", {
            reportId,
            confirmerId,
          });
          break;
        }
      }
    }
    if (!cp) {
      logger.info("Confirmation sans position — pas de notif (comptée).", {
        reportId,
        confirmerId,
      });
      return;
    }
    const reportRef = db.collection("reports").doc(reportId);
    const reportSnap = await reportRef.get();
    if (!reportSnap.exists) return;
    const report = reportSnap.data() as ReportDoc & ReportNotifState;
    if (report.archivedAt) return;

    const epicenters = report.notificationEpicenters ?? [];

    // Garde-fou coût : confirmeur à < EPICENTER_MERGE_M d'un point déjà couvert
    // → on ne relance rien (hors tout premier passage, où il n'y a pas encore
    // d'épicentre).
    if (epicenters.length > 0) {
      const near = epicenters.some(
        (e) => distanceBetween([cp.lat, cp.lng], [e.lat, e.lng]) * 1000 < EPICENTER_MERGE_M
      );
      if (near) {
        logger.info("Épicentre trop proche d'un point déjà couvert — skip.", {
          reportId,
          confirmerId,
        });
        return;
      }
    }

    // Épicentres à couvrir : au 1er passage, le signalement ET le confirmeur
    // (l'événement est validé) ; ensuite, le confirmeur seul.
    const toProcess: GeoPoint[] = [];
    if (epicenters.length === 0 && report.position) toProcess.push(report.position);
    toProcess.push({ lat: cp.lat, lng: cp.lng });

    // On ne notifie jamais l'auteur, le confirmeur, ni les déjà-notifiés.
    const exclude = new Set<string>(report.notifiedUserIds ?? []);
    exclude.add(report.userId);
    exclude.add(confirmerId);

    // Collecte des devices dans NOTIFY_RADIUS_M (distance exacte) autour de
    // chaque épicentre, dédupliqués par token puis filtrés par user.
    const byToken = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
    for (const ep of toProcess) {
      const devices = await devicesWithinRadius(ep, NOTIFY_RADIUS_M);
      for (const d of devices) byToken.set(d.id, d);
    }
    const tokens: string[] = [];
    const newUserIds = new Set<string>();
    for (const d of byToken.values()) {
      const data = d.data() as DeviceDoc;
      if (!data.userId || exclude.has(data.userId)) continue;
      if (data.fcmEnabled === false) continue;
      tokens.push(d.id);
      newUserIds.add(data.userId);
    }

    // Toujours enregistrer les épicentres traités (même si 0 destinataire) pour
    // que le garde-fou coût fonctionne aux prochaines confirmations. Marquer le
    // confirmeur + les nouveaux notifiés.
    await reportRef.update({
      notificationEpicenters:
        admin.firestore.FieldValue.arrayUnion(...toProcess),
      notifiedUserIds: admin.firestore.FieldValue.arrayUnion(
        confirmerId,
        ...Array.from(newUserIds)
      ),
    });

    if (tokens.length === 0) {
      logger.info("Aucun nouveau destinataire dans le rayon.", { reportId });
      return;
    }
    await sendOutageNotif(tokens, reportId, report);
  }
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Devices dont la **position exacte** est à ≤ [radiusM] mètres de [center].
 * Pré-filtre geohash GROSSIER (rayon élargi `PREFILTER_RADIUS_M` pour matcher
 * les geohash devices en précision 6), puis coupe fin à la distance réelle via
 * `device.position`. Les devices sans position (pas encore ré-enregistrés
 * depuis la mise à jour) ne sont pas ciblés — ils le seront au prochain lancement.
 */
async function devicesWithinRadius(
  center: GeoPoint,
  radiusM: number
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const db = admin.firestore();
  const bounds = geohashQueryBounds([center.lat, center.lng], PREFILTER_RADIUS_M);
  const snaps = await Promise.all(
    bounds.map(([start, end]) =>
      db.collection("devices").orderBy("geohash").startAt(start).endAt(end).get()
    )
  );
  const result: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  const seen = new Set<string>();
  for (const s of snaps) {
    for (const d of s.docs) {
      if (seen.has(d.id)) continue;
      const pos = (d.data() as DeviceDoc).position;
      if (!pos || typeof pos.lat !== "number" || typeof pos.lng !== "number") {
        continue;
      }
      if (distanceBetween([center.lat, center.lng], [pos.lat, pos.lng]) * 1000 > radiusM) {
        continue;
      }
      seen.add(d.id);
      result.push(d);
    }
  }
  return result;
}

/**
 * Envoie un multicast FCM par batches de 500 et purge opportunément les
 * tokens morts. [message] = fragment commun (data et/ou notification).
 */
async function sendToTokens(
  tokens: string[],
  message: {
    data?: Record<string, string>;
    notification?: { title: string; body: string };
  }
): Promise<void> {
  const toDelete: string[] = [];
  let sent = 0;
  let failed = 0;

  for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
    const batch = tokens.slice(i, i + BATCH_SIZE);
    // iOS : un message data-only est un push silencieux (throttlé, souvent
    // invisible). Pour les vagues de proximité (data-only avec title/body dans
    // data), on ajoute un habillage APNs = alerte visible côté iOS, pendant
    // qu'Android garde le data-only (notification locale avec boutons de vote).
    const iosAlert =
      !message.notification && message.data?.title && message.data?.body
        ? {
            apns: {
              payload: {
                aps: {
                  alert: {
                    title: message.data.title,
                    body: message.data.body,
                  },
                  sound: "default",
                },
              },
            },
          }
        : {};
    const resp = await admin.messaging().sendEachForMulticast({
      tokens: batch,
      ...(message.data ? { data: message.data } : {}),
      ...(message.notification ? { notification: message.notification } : {}),
      ...iosAlert,
      android: {
        priority: "high",
        ...(message.notification
          ? {
              notification: {
                channelId: OUTAGE_CHANNEL_ID,
                priority: "high" as const,
              },
            }
          : {}),
      },
    });
    sent += resp.successCount;
    failed += resp.failureCount;
    resp.responses.forEach((r, idx) => {
      if (r.success) return;
      const code = r.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-argument" ||
        code === "messaging/invalid-registration-token"
      ) {
        toDelete.push(batch[idx]);
      } else {
        logger.warn("Envoi FCM échoué", {
          token: batch[idx].slice(0, 12) + "…",
          code,
          message: r.error?.message,
        });
      }
    });
  }
  logger.info(`FCM résultats — envoyé:${sent} échec:${failed}`);

  if (toDelete.length > 0) {
    const db = admin.firestore();
    await Promise.all(
      toDelete.map((token) =>
        db
          .collection("devices")
          .doc(token)
          .delete()
          .catch((e) =>
            logger.warn("Échec delete token", { token: token.slice(0, 12), e })
          )
      )
    );
  }
}

/**
 * Envoie la notif « Coupure à proximité » aux [tokens].
 *
 * Message **data-only** (pas de bloc `notification`) : c'est l'app qui
 * affiche la notif via flutter_local_notifications, ce qui permet d'y
 * attacher les BOUTONS D'ACTION « Chez moi aussi / Pas chez moi » (vote en
 * 1 tap sans ouvrir l'app). ⚠️ Nécessite l'app ≥ 1.2.0+51 : les versions
 * antérieures n'affichent rien pour un message data-only en arrière-plan.
 */
async function sendOutageNotif(
  tokens: string[],
  reportId: string,
  report: ReportDoc
): Promise<void> {
  await sendToTokens(tokens, {
    data: {
      reportId,
      type: report.type ?? report.cause ?? "unplanned",
      serviceType: report.serviceType ?? "electricity",
      title: "Coupure à proximité",
      body: buildBody(report.location),
    },
  });
}

/**
 * Récompense du confirmeur (« confirme → sois prévenu du retour ») : quand
 * une coupure passe en `resolved` (auto-résolution OU résolution manuelle),
 * on notifie **l'auteur et les confirmeurs** que le service est revenu —
 * SAUF ceux qui ont eux-mêmes déclaré le retour (ils le savent déjà).
 * Message classique (bloc `notification`) : pas de boutons nécessaires,
 * compatible toutes versions d'app ; le tap ouvre le détail (reportId).
 */
export const onReportResolved = onDocumentUpdated(
  "reports/{reportId}",
  async (event) => {
    const before = event.data?.before.data() as
      | (ReportDoc & { status?: string })
      | undefined;
    const after = event.data?.after.data() as
      | (ReportDoc & { status?: string })
      | undefined;
    if (!before || !after) return;
    // Uniquement la TRANSITION vers resolved (pas les updates ultérieurs).
    if (before.status === "resolved" || after.status !== "resolved") return;
    if (after.archivedAt) return;
    const reportId = event.params.reportId as string;

    const db = admin.firestore();
    const reportRef = db.collection("reports").doc(reportId);
    const [confs, restos] = await Promise.all([
      reportRef.collection("confirmations").get(),
      reportRef.collection("restorations").get(),
    ]);
    const alreadyKnow = new Set(restos.docs.map((d) => d.id));
    const uids = new Set<string>();
    confs.docs.forEach((d) => {
      if (!alreadyKnow.has(d.id)) uids.add(d.id);
    });
    if (after.userId && !alreadyKnow.has(after.userId)) uids.add(after.userId);
    if (uids.size === 0) {
      logger.info("Résolution sans destinataire à prévenir.", { reportId });
      return;
    }

    // Tokens des devices de ces utilisateurs (paquets de 10 — limite `in`).
    const tokens: string[] = [];
    const uidArr = Array.from(uids);
    for (let i = 0; i < uidArr.length; i += 10) {
      const chunk = uidArr.slice(i, i + 10);
      const snap = await db
        .collection("devices")
        .where("userId", "in", chunk)
        .get();
      snap.docs.forEach((d) => {
        const data = d.data() as DeviceDoc;
        if (data.fcmEnabled === false) return;
        tokens.push(d.id);
      });
    }
    if (tokens.length === 0) {
      logger.info("Résolution : aucun device à notifier.", { reportId });
      return;
    }

    const { title, body } = resolvedNotifContent(
      after.serviceType,
      after.location
    );
    logger.info(
      `Résolution de ${reportId} : notification de ${tokens.length} device(s).`
    );
    await sendToTokens(tokens, {
      notification: { title, body },
      data: { reportId, type: "outage_resolved" },
    });
  }
);

/**
 * Auto-résolution crowd-sourcée : à chaque nouvelle déclaration « courant
 * revenu chez moi » (`restorations/{uid}`), on vérifie si le seuil est franchi
 * et, si oui, on bascule le report en `resolved` avec `resolvedAt` côté
 * serveur. Pattern symétrique aux confirmations : aucune action de l'auteur
 * n'est requise, les voisins ferment la coupure collectivement.
 */
export const onRestorationCreated = onDocumentCreated(
  "reports/{reportId}/restorations/{uid}",
  async (event) => {
    const reportId = event.params.reportId;
    const db = admin.firestore();
    const reportRef = db.collection("reports").doc(reportId);
    const snap = await reportRef.get();
    if (!snap.exists) {
      logger.warn(`onRestorationCreated: report ${reportId} introuvable.`);
      return;
    }
    const report = snap.data() as ReportDoc & {
      status?: string;
      confirmationCount?: number;
      restorationCount?: number;
    };
    const confirmations = report.confirmationCount ?? 0;
    const restorations = report.restorationCount ?? 0;
    const threshold = resolutionThreshold(confirmations, effectiveMinVotes());

    logger.info(
      `onRestorationCreated: report=${reportId} restorations=${restorations} ` +
        `confirmations=${confirmations} threshold=${threshold}`
    );

    // Décision (statut/archivage/seuil) centralisée et testée dans ./logic.
    if (!shouldResolve(report)) return;

    await reportRef.update({
      status: "resolved",
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info(`onRestorationCreated: report ${reportId} → resolved.`);
  }
);

/**
 * Interrupteur de la purge automatique. **Désactivé pour l'instant** (demande
 * produit 2026-06-15) : les reports archivés ne sont PLUS supprimés
 * définitivement. Le cron reste déployé mais ne fait rien. Repasser à `true`
 * (et redéployer les functions) pour réactiver la purge.
 */
const PURGE_ARCHIVED_ENABLED = false;

/**
 * Cron quotidien : purge définitive (hard delete) des reports archivés depuis
 * plus de [ARCHIVED_RETENTION_DAYS] jours. La suppression est **récursive** :
 * sous-collections `confirmations` et `restorations` incluses (sinon elles
 * deviennent orphelines puisque Firestore ne cascade pas).
 */
export const purgeArchivedReports = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Africa/Douala",
    retryCount: 0,
  },
  async () => {
    if (!PURGE_ARCHIVED_ENABLED) {
      logger.info("purgeArchivedReports: désactivé (PURGE_ARCHIVED_ENABLED=false) — aucune purge.");
      return;
    }
    const db = admin.firestore();
    const cutoff = new Date(
      Date.now() - ARCHIVED_RETENTION_DAYS * 24 * 60 * 60 * 1000
    );
    const stale = await db
      .collection("reports")
      .where("archivedAt", "<", cutoff)
      .get();
    logger.info(
      `purgeArchivedReports: ${stale.size} report(s) à supprimer ` +
        `(cutoff=${cutoff.toISOString()})`
    );
    if (stale.empty) return;

    // recursiveDelete supprime le doc + ses sous-collections en un appel.
    for (const doc of stale.docs) {
      try {
        await db.recursiveDelete(doc.ref);
      } catch (e) {
        logger.warn(`purgeArchivedReports: échec sur ${doc.id}`, e);
      }
    }
    logger.info(`purgeArchivedReports: ${stale.size} report(s) purgé(s).`);
  }
);

/**
 * Cron quotidien : supprime les devices dont `updatedAt` est plus ancien que
 * [STALE_DEVICE_AGE_DAYS]. Utile pour les comptes désinstallés silencieusement
 * (pas de logout, donc pas de deleteDevice client-side) — ces tokens
 * accumulent autrement et provoquent des envois inutiles (qu'on purge au coup
 * par coup via [onReportCreated], mais ça ne couvre que les tokens
 * **invalides**, pas ceux qui restent valides mais sont inactifs).
 */
export const purgeStaleDevices = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Africa/Douala",
    retryCount: 0,
  },
  async () => {
    const db = admin.firestore();
    const cutoff = new Date(
      Date.now() - STALE_DEVICE_AGE_DAYS * 24 * 60 * 60 * 1000
    );
    const stale = await db
      .collection("devices")
      .where("updatedAt", "<", cutoff)
      .get();
    logger.info(
      `purgeStaleDevices: ${stale.size} device(s) à supprimer (cutoff=${cutoff.toISOString()})`
    );
    if (stale.empty) return;

    // Suppression par batchs de 500 (limite Firestore).
    for (let i = 0; i < stale.docs.length; i += BATCH_SIZE) {
      const batch = db.batch();
      stale.docs
        .slice(i, i + BATCH_SIZE)
        .forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
    logger.info(`purgeStaleDevices: ${stale.size} device(s) supprimé(s).`);
  }
);

/**
 * Suppression de compte (RGPD / exigence stores). Callable, appelée par
 * l'utilisateur authentifié après ré-authentification côté client.
 *
 * Stratégie « Option B » :
 *  - **Signalements** de l'utilisateur → **anonymisés** (on retire `userId`,
 *    `authorUsername` et `mediaUrl`) : la coupure reste un repère communautaire
 *    mais ne porte plus de donnée personnelle.
 *  - **Profil**, **index pseudo**, **devices** (tokens FCM), **médias Storage**
 *    et **compte Auth** → **supprimés**.
 *
 * Le compte Auth est supprimé en DERNIER : si le nettoyage des données échoue,
 * l'utilisateur reste connecté et peut réessayer (pas de données orphelines
 * sans propriétaire).
 */
export const deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentification requise.");
  }
  const db = admin.firestore();
  logger.info(`deleteAccount: début pour ${uid}`);

  const commitInChunks = async (
    docs: FirebaseFirestore.QueryDocumentSnapshot[],
    apply: (
      batch: FirebaseFirestore.WriteBatch,
      ref: FirebaseFirestore.DocumentReference
    ) => void
  ) => {
    for (let i = 0; i < docs.length; i += 500) {
      const batch = db.batch();
      docs.slice(i, i + 500).forEach((d) => apply(batch, d.ref));
      await batch.commit();
    }
  };

  // 1. Anonymiser les signalements de l'utilisateur (Option B).
  const reports = await db
    .collection("reports")
    .where("userId", "==", uid)
    .get();
  await commitInChunks(reports.docs, (batch, ref) =>
    batch.update(ref, {
      userId: "",
      authorUsername: null,
      mediaUrl: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    })
  );
  logger.info(`deleteAccount: ${reports.size} signalement(s) anonymisé(s).`);

  // 2. Supprimer les devices (tokens FCM) de l'utilisateur.
  const devices = await db
    .collection("devices")
    .where("userId", "==", uid)
    .get();
  await commitInChunks(devices.docs, (batch, ref) => batch.delete(ref));

  // 3. Supprimer l'index pseudo (résolu depuis le doc user).
  const userSnap = await db.collection("users").doc(uid).get();
  const username = userSnap.data()?.username as string | undefined;
  if (username) {
    await db
      .collection("usernames")
      .doc(username)
      .delete()
      .catch((e) => logger.warn("deleteAccount: échec delete username", e));
  }

  // 4. Supprimer le profil.
  await db.collection("users").doc(uid).delete();

  // 5. Supprimer les médias Storage de l'utilisateur.
  await admin
    .storage()
    .bucket()
    .deleteFiles({ prefix: `report_media/${uid}/` })
    .catch((e) => logger.warn("deleteAccount: échec delete médias", e));

  // 6. Supprimer le compte Auth (en dernier).
  await admin.auth().deleteUser(uid);
  logger.info(`deleteAccount: compte ${uid} supprimé.`);

  return { ok: true };
});

/* ──────────────────────────────────────────────────────────────────────────
 * Ingestion des coupures officielles planifiées (Eneo + futurs fournisseurs).
 * Couche distincte des signalements communautaires (planifié ≠ délestage
 * vécu). Alimente `official_outages/` via l'Admin SDK uniquement.
 * ────────────────────────────────────────────────────────────────────────── */

const OFFICIAL_OUTAGES_COLLECTION = "official_outages";

/** Date du jour au format YYYY-MM-DD dans le fuseau Africa/Douala. */
function todayInDouala(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Douala",
  }).format(new Date());
}

/**
 * Récupère le programme Eneo, normalise, upsert dans `official_outages/`
 * (idempotent via `rawHash`), puis purge les entrées dont la date est passée.
 * Partagé par le cron et le déclencheur HTTP de test.
 */
export async function runEneoIngestion(): Promise<{
  upserted: number;
  pruned: number;
}> {
  const db = admin.firestore();
  const adapter = new EneoAdapter();
  const raw = await adapter.fetch();
  const outages = adapter.normalize(raw);
  logger.info(
    `ingestEneoOutages: ${raw.length} brut(s) → ${outages.length} normalisé(s)`
  );

  // Upsert par lots de [BATCH_SIZE] (merge → conserve fetchedAt cohérent).
  let upserted = 0;
  for (let i = 0; i < outages.length; i += BATCH_SIZE) {
    const slice = outages.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    for (const o of slice) {
      const ref = db
        .collection(OFFICIAL_OUTAGES_COLLECTION)
        .doc(o.rawHash);
      batch.set(
        ref,
        {
          provider: o.provider,
          country: o.country,
          region: o.region,
          ville: o.ville,
          quartier: o.quartier,
          reason: o.reason,
          progDate: o.progDate,
          startTime: o.startTime,
          endTime: o.endTime,
          startsAt: admin.firestore.Timestamp.fromDate(o.startsAt),
          endsAt: admin.firestore.Timestamp.fromDate(o.endsAt),
          sourceUrl: o.sourceUrl,
          fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    await batch.commit();
    upserted += slice.length;
  }

  // Purge des entrées passées (progDate < aujourd'hui, fuseau Douala).
  const today = todayInDouala();
  const stale = await db
    .collection(OFFICIAL_OUTAGES_COLLECTION)
    .where("progDate", "<", today)
    .get();
  let pruned = 0;
  for (let i = 0; i < stale.docs.length; i += BATCH_SIZE) {
    const slice = stale.docs.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    slice.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    pruned += slice.length;
  }

  logger.info(
    `ingestEneoOutages: ${upserted} upsert(s), ${pruned} purgé(s) (cutoff ${today}).`
  );
  return { upserted, pruned };
}

/** Cron quotidien : importe le programme officiel Eneo. */
export const ingestEneoOutages = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "Africa/Douala",
    retryCount: 0,
  },
  async () => {
    await runEneoIngestion();
  }
);

// Test manuel en émulateur : pas de déclencheur HTTP — le worker HTTPS de
// l'émulateur firebase-tools plante avec firebase-functions v7. On lance
// l'ingestion en direct via `functions/scripts/seedEneo.cjs` sous
// `firebase emulators:exec --only firestore` (voir tasks/TESTS-MANUELS.md).

/* ──────────────────────────────────────────────────────────────────────────
 * Alerte push : prévient les utilisateurs qui SUIVENT un quartier (clé
 * `REGION|VILLE|QUARTIER`, champ `users.followedQuartiers`) la veille d'une
 * coupure planifiée. Réutilise FCM. Tourne le soir (Africa/Douala).
 * ────────────────────────────────────────────────────────────────────────── */

/** Date YYYY-MM-DD à +[days] jours, dans le fuseau Africa/Douala. */
function dateInDoualaPlusDays(days: number): string {
  const shifted = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Douala",
  }).format(shifted);
}

async function runFollowedOutageAlerts(): Promise<{
  quartiers: number;
  sent: number;
}> {
  const db = admin.firestore();
  const target = dateInDoualaPlusDays(1); // demain
  const snap = await db
    .collection(OFFICIAL_OUTAGES_COLLECTION)
    .where("progDate", "==", target)
    .get();
  if (snap.empty) {
    logger.info(`alertFollowedOutages: aucune coupure planifiée le ${target}`);
    return { quartiers: 0, sent: 0 };
  }

  // Regroupe par clé de quartier (une alerte par quartier).
  const byKey = new Map<
    string,
    { quartier: string; startTime?: string; endTime?: string }
  >();
  for (const d of snap.docs) {
    const o = d.data();
    const key = `${o.region}|${o.ville}|${o.quartier}`;
    if (!byKey.has(key)) {
      byKey.set(key, {
        quartier: o.quartier,
        startTime: o.startTime,
        endTime: o.endTime,
      });
    }
  }

  let sent = 0;
  for (const [key, info] of byKey) {
    const usersSnap = await db
      .collection("users")
      .where("followedQuartiers", "array-contains", key)
      .get();
    if (usersSnap.empty) continue;
    const uids = usersSnap.docs.map((d) => d.id);

    // Tokens des devices de ces utilisateurs (paquets de 10 — limite `in`).
    const tokens: string[] = [];
    for (let i = 0; i < uids.length; i += 10) {
      const chunk = uids.slice(i, i + 10);
      const devSnap = await db
        .collection("devices")
        .where("userId", "in", chunk)
        .get();
      devSnap.docs.forEach((d) => {
        const data = d.data() as DeviceDoc;
        if (data.fcmEnabled === false) return;
        tokens.push(d.id);
      });
    }
    if (tokens.length === 0) continue;

    const body = plannedAlertBody(info);
    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const batch = tokens.slice(i, i + BATCH_SIZE);
      const resp = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: { title: "Coupure planifiée demain", body },
        data: { type: "planned_outage", followKey: key },
        android: {
          priority: "high",
          notification: { channelId: OUTAGE_CHANNEL_ID, priority: "high" },
        },
      });
      sent += resp.successCount;
    }
  }

  logger.info(
    `alertFollowedOutages (${target}): ${sent} notif(s) sur ${byKey.size} quartier(s) suivi(s).`
  );
  return { quartiers: byKey.size, sent };
}

/** Cron quotidien (soir) : alerte les abonnés des coupures planifiées du lendemain. */
export const alertFollowedOutages = onSchedule(
  {
    schedule: "0 19 * * *",
    timeZone: "Africa/Douala",
    retryCount: 0,
  },
  async () => {
    await runFollowedOutageAlerts();
  }
);
