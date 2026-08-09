/**
 * « Toujours coupé » (ping du cycle de vie) — callable minimaliste : la seule
 * écriture légale côté client serait bloquée par les règles (un non-auteur ne
 * peut pas toucher `updatedAt`). Ici : Admin SDK, vérifications strictes,
 * effet unique = rafraîchir l'activité de la coupure (tache vive + le chrono
 * d'expiration 48 h repart). Aucun compteur touché — pas de donnée fabriquée.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

export const markStillOut = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentification requise.");
  const reportId = String(request.data?.reportId ?? "");
  if (!/^[A-Za-z0-9_-]{5,40}$/.test(reportId)) {
    throw new HttpsError("invalid-argument", "reportId invalide.");
  }
  const ref = admin.firestore().collection("reports").doc(reportId);
  const snap = await ref.get();
  const data = snap.data();
  if (!snap.exists || !data || data.archivedAt || data.status !== "ongoing") {
    return { refreshed: false };
  }
  await ref.update({
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { refreshed: true };
});
