#!/usr/bin/env node
/**
 * Envoi d'une notification FCM de test à un token précis.
 *
 * Usage :
 *   node functions/scripts/send-test-fcm.js <token-fcm> [reportId]
 *
 * - Le token est récupéré dans les logs `flutter run` ([FCM] FULL TOKEN).
 * - reportId (optionnel) : ajoute une donnée `reportId` au payload pour
 *   tester la navigation au tap.
 *
 * Pré-requis :
 *   gcloud auth application-default login
 */

const admin = require("firebase-admin");

const [, , token, reportId] = process.argv;
if (!token) {
  console.error("Usage: node send-test-fcm.js <token-fcm> [reportId]");
  process.exit(1);
}

admin.initializeApp({
  projectId: "lightcutoff-dev",
  credential: admin.credential.applicationDefault(),
});

const message = {
  token,
  notification: {
    title: "Coupure à proximité",
    body: "Quartier Bastos · à l'instant (test depuis le Mac)",
  },
  data: reportId ? { reportId } : {},
  android: {
    // Priorité LIVRAISON (bypass le batching de Google FCM, livraison immédiate
    // même en Doze / sur émulateur).
    priority: "high",
    notification: {
      // Doit correspondre à AppConstants.fcmOutageChannelId côté app.
      channelId: "njuka_outage_alerts",
      // Priorité AFFICHAGE (heads-up).
      priority: "high",
    },
  },
};

admin
  .messaging()
  .send(message)
  .then((id) => {
    console.log("✓ message envoyé, messageId:", id);
    process.exit(0);
  })
  .catch((err) => {
    console.error("❌ envoi échoué:");
    console.error("  code:", err.code);
    console.error("  message:", err.message);
    if (err.errorInfo) console.error("  errorInfo:", err.errorInfo);
    process.exit(1);
  });
