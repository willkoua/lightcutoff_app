/**
 * Simule une vague de notification de proximité (test du flux complet) :
 *   1. crée un signalement seedé à ~200 m de LAT/LNG (auteur fictif) ;
 *   2. crée une confirmation (uid fictif, position = LAT/LNG) →
 *      déclenche `onConfirmationCreated` → notif avec boutons de vote sur
 *      tous les devices à < 500 m ayant un champ `position`.
 *
 * Usage :
 *   GCLOUD_PROJECT=lightcutoff-dev node scripts/simulateWave.cjs <lat> <lng>
 * (ADC gcloud requis. Affiche d'abord les devices ciblables pour vérifier.)
 */
const admin = require("firebase-admin");

const PROJECT = process.env.GCLOUD_PROJECT || "lightcutoff-dev";
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const Ts = admin.firestore.Timestamp;

const B32 = "0123456789bcdefghjkmnpqrstuvwxyz";
function geohash(lat, lng, precision = 6) {
  let latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
  let hash = "", even = true, bit = 0, ch = 0;
  while (hash.length < precision) {
    if (even) {
      const mid = (lngMin + lngMax) / 2;
      if (lng >= mid) { ch = (ch << 1) | 1; lngMin = mid; } else { ch = ch << 1; lngMax = mid; }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latMin = mid; } else { ch = ch << 1; latMax = mid; }
    }
    even = !even;
    if (++bit === 5) { hash += B32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

function distM(a, b) {
  const R = 6371000, rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

(async () => {
  const lat = parseFloat(process.argv[2]);
  const lng = parseFloat(process.argv[3]);
  if (Number.isNaN(lat) || Number.isNaN(lng)) {
    console.error("Usage: node scripts/simulateWave.cjs <lat> <lng>");
    process.exit(1);
  }

  // 0. Devices ciblables (position exacte à < 500 m) — sanity check.
  const devices = await db.collection("devices").get();
  let targetable = 0;
  devices.docs.forEach((d) => {
    const data = d.data();
    if (!data.position) return;
    const dist = Math.round(distM({ lat, lng }, data.position));
    if (dist <= 500) {
      targetable++;
      console.log(
        `  device ${d.id.slice(0, 12)}… uid=${(data.userId || "?").slice(0, 8)}… ` +
        `à ${dist} m · fcmEnabled=${data.fcmEnabled !== false}`
      );
    }
  });
  console.log(`Devices ciblables (<500 m, avec position) : ${targetable}`);
  if (targetable === 0) {
    console.warn("⚠️ Aucun device ciblable — la notif n'arrivera nulle part.");
  }

  // 1. Report à ~200 m au nord (0.0018° lat ≈ 200 m), auteur fictif.
  const rLat = lat + 0.0018, rLng = lng;
  const now = Date.now();
  const reportRef = await db.collection("reports").add({
    userId: "seed_wave_author",
    status: "ongoing",
    type: "unplanned",
    serviceType: "electricity",
    position: { lat: rLat, lng: rLng },
    location: {
      country: "Canada", countryCode: "CA", region: "Québec",
      city: "Montréal", neighborhood: "Test vague",
    },
    description: "Coupure simulée pour tester les notifications (à supprimer).",
    mediaUrl: null,
    authorUsername: null,
    geohash: geohash(rLat, rLng),
    confirmationCount: 1,
    restorationCount: 0,
    reportedAt: Ts.fromMillis(now - 10 * 60 * 1000),
    resolvedAt: null,
    archivedAt: null,
    createdAt: Ts.fromMillis(now - 10 * 60 * 1000),
    updatedAt: Ts.fromMillis(now),
  });
  console.log(`Report créé : ${reportRef.id} (${rLat.toFixed(5)}, ${rLng})`);

  // 2. Confirmation fictive À TA POSITION → déclenche la vague.
  await reportRef.collection("confirmations").doc("seed_wave_confirmer").set({
    createdAt: Ts.fromMillis(now),
    geohash: geohash(lat, lng),
    position: { lat, lng },
  });
  console.log("Confirmation créée → onConfirmationCreated va tirer la vague.");
  console.log(`Nettoyage ensuite : supprimer le report ${reportRef.id}.`);
  process.exit(0);
})().catch((e) => { console.error("Échec:", e); process.exit(1); });
