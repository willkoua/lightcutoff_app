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
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { geohashQueryBounds } from "geofire-common";
import {
  buildBody,
  plannedAlertBody,
  resolutionThreshold,
  shouldResolve,
} from "./logic";
import { EneoAdapter } from "./sources/eneo";

admin.initializeApp();

const NOTIFY_RADIUS_M = 2000;
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
  archivedAt?: FirebaseFirestore.Timestamp | null;
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

    // Garde : report déjà archivé (cas improbable mais défensif).
    if (report.archivedAt) {
      logger.info("Report déjà archivé — pas de notification.");
      return;
    }

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
    const confirmations = report.confirmationCount ?? 0;
    const restorations = report.restorationCount ?? 0;
    const threshold = resolutionThreshold(confirmations);

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
