/**
 * Smoke test des notifs de proximité (A — notif à la création).
 *
 * Crée un signalement à une position donnée, AU NOM d'un auteur factice
 * (`smoke_author`) pour que TON device (≠ auteur) ne soit pas exclu et reçoive
 * bien « Coupure à proximité ». `onReportCreated` (déployé sur le projet ciblé)
 * notifie alors les devices à ≤ 500 m.
 *
 * Usage :
 *   # position auto (celle du device le plus récent — lance l'app d'abord,
 *   # localisation accordée, pour qu'un device avec position existe) :
 *   GCLOUD_PROJECT=lightcutoff-dev node scripts/smokeNotif.cjs
 *   # ou position explicite :
 *   GCLOUD_PROJECT=lightcutoff-dev node scripts/smokeNotif.cjs -1.2921 36.8219
 *
 * ⚠️ Crée de la donnée de test : le script affiche l'id du report pour le
 *    supprimer après (`node scripts/smokeNotif.cjs --purge <reportId>`).
 */
const admin = require("firebase-admin");
const { geohashForLocation } = require("geofire-common");

const proj = process.env.GCLOUD_PROJECT;
if (!proj) {
  console.error("Définis GCLOUD_PROJECT (ex. lightcutoff-dev).");
  process.exit(1);
}
admin.initializeApp({ projectId: proj });
const db = admin.firestore();

(async () => {
  // Purge d'un report de test : node scripts/smokeNotif.cjs --purge <id>
  if (process.argv[2] === "--purge") {
    const id = process.argv[3];
    if (!id) {
      console.error("Usage: --purge <reportId>");
      process.exit(1);
    }
    await db.recursiveDelete(db.collection("reports").doc(id));
    console.log(`Report ${id} supprimé.`);
    process.exit(0);
  }

  let lat = Number.parseFloat(process.argv[2]);
  let lng = Number.parseFloat(process.argv[3]);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    // Position auto : on prend un device qui a une position (= ton téléphone,
    // après avoir lancé l'app avec la localisation accordée).
    const devs = await db.collection("devices").get();
    const withPos = devs.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .filter((x) => x.position && typeof x.position.lat === "number");
    if (withPos.length === 0) {
      console.error(
        "Aucun device avec position. Lance l'app (localisation accordée) " +
          "pour enregistrer un device, ou passe une position : <lat> <lng>."
      );
      process.exit(1);
    }
    lat = withPos[0].position.lat;
    lng = withPos[0].position.lng;
    console.log(
      `Position auto depuis un device: ${lat.toFixed(5)}, ${lng.toFixed(5)} ` +
        `(userId=${withPos[0].userId})`
    );
  }

  const geohash = geohashForLocation([lat, lng]);
  const ref = await db.collection("reports").add({
    userId: "smoke_author", // ≠ ton compte → tu n'es PAS exclu de la notif
    position: { lat, lng },
    location: {
      country: "KE",
      countryCode: "KE",
      city: "Nairobi",
      neighborhood: "Smoke Test",
    },
    geohash,
    serviceType: "electricity",
    type: "unplanned",
    status: "ongoing",
    confirmationCount: 0,
    restorationCount: 0,
    reportedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(
    `\n✅ Report créé: ${ref.id} @ ${lat.toFixed(5)}, ${lng.toFixed(5)}`
  );
  console.log(
    "→ onReportCreated doit notifier les devices à ≤ 500 m (sauf smoke_author)."
  );
  console.log(
    `\nLogs: gcloud functions logs read onReportCreated --project=${proj} --limit=10` +
      "  (ou vérifie la notif sur le téléphone)"
  );
  console.log(`Nettoyage ensuite: node scripts/smokeNotif.cjs --purge ${ref.id}`);
  process.exit(0);
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
