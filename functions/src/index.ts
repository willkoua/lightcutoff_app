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
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { geohashQueryBounds } from "geofire-common";

admin.initializeApp();

const NOTIFY_RADIUS_M = 2000;
const BATCH_SIZE = 500;
const OUTAGE_CHANNEL_ID = "njuka_outage_alerts";
const STALE_DEVICE_AGE_DAYS = 90;

// Auto-résolution crowd-sourcée : un report passe à `resolved` quand
// restorationCount >= max(RESTORATION_MIN_VOTES, confirmationCount * RESTORATION_RATIO).
// Doit rester aligné avec `AppConstants.restorationMinVotes` / `restorationRatio` côté Dart.
const RESTORATION_MIN_VOTES = 3;
const RESTORATION_RATIO = 0.5;

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
}

interface DeviceDoc {
  userId: string;
  platform?: string;
  homeLocation?: GeoArea;
  geohash?: string;
  fcmEnabled?: boolean;
}

export const onReportCreated = onDocumentCreated(
  "reports/{reportId}",
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn("Pas de snapshot dans l'event, abandon.");
      return;
    }
    const report = snap.data() as ReportDoc;
    const reportId = event.params.reportId;
    const authorId = report.userId;

    logger.info("onReportCreated", { reportId, authorId, type: report.type });

    // 1. Récupération des devices candidats.
    const candidates = await collectCandidates(report, authorId);
    if (candidates.length === 0) {
      logger.info("Aucun device candidat — pas d'envoi.");
      return;
    }
    logger.info(`${candidates.length} device(s) candidat(s) à notifier.`);

    // 2. Construction du payload commun.
    const body = buildBody(report.location);
    const dataPayload: Record<string, string> = {
      reportId,
      type: report.type ?? report.cause ?? "unplanned",
    };

    // 3. Envoi par batches de 500 (limite FCM).
    const tokens = candidates.map((d) => d.id);
    const toDelete: string[] = [];
    let sent = 0;
    let failed = 0;

    for (let i = 0; i < tokens.length; i += BATCH_SIZE) {
      const batch = tokens.slice(i, i + BATCH_SIZE);
      const resp = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        notification: {
          title: "Coupure à proximité",
          body,
        },
        data: dataPayload,
        android: {
          priority: "high",
          notification: {
            channelId: OUTAGE_CHANNEL_ID,
            priority: "high",
          },
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

    // 4. Purge opportuniste des tokens morts.
    if (toDelete.length > 0) {
      logger.info(`Purge de ${toDelete.length} token(s) périmé(s).`);
      const db = admin.firestore();
      await Promise.all(
        toDelete.map((token) =>
          db
            .collection("devices")
            .doc(token)
            .delete()
            .catch((e) =>
              logger.warn("Échec delete token", {
                token: token.slice(0, 12),
                e,
              })
            )
        )
      );
    }
  }
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Retourne la liste des devices candidats à notifier (déjà filtrés sur
 * `fcmEnabled` et l'exclusion de l'auteur). Doublons éventuels écartés.
 */
async function collectCandidates(
  report: ReportDoc,
  authorId: string
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const db = admin.firestore();
  const seen = new Set<string>();
  const result: FirebaseFirestore.QueryDocumentSnapshot[] = [];

  const pushUnique = (doc: FirebaseFirestore.QueryDocumentSnapshot) => {
    if (seen.has(doc.id)) return;
    const data = doc.data() as DeviceDoc;
    if (data.userId === authorId) return;
    if (data.fcmEnabled === false) return;
    seen.add(doc.id);
    result.push(doc);
  };

  // Voie 1 : devices avec geohash, dans les bounds calculés par geofire.
  if (report.position) {
    const center: [number, number] = [report.position.lat, report.position.lng];
    const bounds = geohashQueryBounds(center, NOTIFY_RADIUS_M);
    const geoQueries = bounds.map(([start, end]) =>
      db
        .collection("devices")
        .orderBy("geohash")
        .startAt(start)
        .endAt(end)
        .get()
    );
    const snapshots = await Promise.all(geoQueries);
    snapshots.forEach((s) => s.docs.forEach(pushUnique));
  }

  // Voie 2 (fallback) : devices sans geohash mais dont la résidence est dans
  // la même ville que le report.
  const city = report.location?.city;
  if (city) {
    const citySnap = await db
      .collection("devices")
      .where("homeLocation.city", "==", city)
      .get();
    // On ne reprend QUE ceux qui n'ont pas de geohash (les autres ont déjà été
    // traités par la voie 1, ou ne sont volontairement pas à proximité).
    citySnap.docs.forEach((d) => {
      const data = d.data() as DeviceDoc;
      if (!data.geohash) pushUnique(d);
    });
  }

  return result;
}

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
    if (report.status === "resolved") return; // déjà fermé

    const confirmations = report.confirmationCount ?? 0;
    const restorations = report.restorationCount ?? 0;
    const threshold = Math.max(
      RESTORATION_MIN_VOTES,
      Math.ceil(confirmations * RESTORATION_RATIO)
    );

    logger.info(
      `onRestorationCreated: report=${reportId} restorations=${restorations} ` +
        `confirmations=${confirmations} threshold=${threshold}`
    );

    if (restorations < threshold) return;

    await reportRef.update({
      status: "resolved",
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    logger.info(`onRestorationCreated: report ${reportId} → resolved.`);
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

/** Construit le corps de la notif à partir de la zone du report. */
function buildBody(area: GeoArea | undefined): string {
  if (!area) return "Une coupure vient d'être signalée près de chez vous.";
  const parts = [area.neighborhood, area.city].filter(
    (s): s is string => !!s && s.length > 0
  );
  if (parts.length === 0) {
    return "Une coupure vient d'être signalée près de chez vous.";
  }
  return `${parts.join(", ")} · à l'instant`;
}
