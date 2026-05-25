#!/usr/bin/env node
/**
 * Crée un signalement de test dans le Firestore prod (pas l'émulateur), avec
 * un `userId` factice — utile pour tester la Cloud Function `onReportCreated`
 * sans être l'auteur (le trigger exclut l'auteur des notifs).
 *
 * Usage :
 *   node functions/scripts/seed-test-report.js [lat] [lng] [city]
 *
 * Défaut : Yaoundé (3.848, 11.502).
 *
 * Pré-requis : gcloud auth application-default login.
 */

const admin = require("firebase-admin");
const { geohashForLocation } = require("geofire-common");

const [, , latArg, lngArg, cityArg] = process.argv;
const lat = parseFloat(latArg) || 3.848;
const lng = parseFloat(lngArg) || 11.502;
const city = cityArg || "Yaoundé";

admin.initializeApp({
  projectId: "lightcutoff-dev",
  credential: admin.credential.applicationDefault(),
});

const geohash = geohashForLocation([lat, lng]).slice(0, 6);

const report = {
  userId: "fake-author-uid-for-test", // n'est PAS le user du téléphone testeur
  status: "ongoing",
  type: "unplanned",
  position: { lat, lng },
  location: { city, country: "Cameroun" },
  description: "Signalement de test injecté pour valider la Cloud Function.",
  geohash,
  authorUsername: "test-bot",
  confirmationCount: 0,
  reportedAt: admin.firestore.FieldValue.serverTimestamp(),
  resolvedAt: null,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};

admin
  .firestore()
  .collection("reports")
  .add(report)
  .then((ref) => {
    console.log(`✓ Report créé: ${ref.id}`);
    console.log(
      `  position=${lat},${lng} geohash=${geohash} city=${city}`
    );
    console.log(
      "→ Le trigger onReportCreated devrait s'exécuter et notifier les devices proches."
    );
    process.exit(0);
  })
  .catch((err) => {
    console.error("❌ Échec :", err.message);
    process.exit(1);
  });
