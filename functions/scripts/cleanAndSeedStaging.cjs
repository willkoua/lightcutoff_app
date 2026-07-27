/**
 * Nettoie la collection `reports` de staging (lightcutoff-dev) et la re-seede
 * avec des coupures CRÉDIBLES (Cameroun, électricité + eau) pour des captures
 * d'écran Play Store présentables — descriptions naturelles, aucune mention de
 * « test ».
 *
 * Lancer : node functions/scripts/cleanAndSeedStaging.cjs
 * (utilise les identifiants gcloud ADC déjà présents)
 */
const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "lightcutoff-dev",
});
const db = admin.firestore();
const FV = admin.firestore.FieldValue;
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

const CM = { country: "Cameroun", countryCode: "CM" };
const HOUR = 3600 * 1000;
const now = Date.now();

// 3 coupures d'électricité + 3 coupures d'eau, Yaoundé/Douala, descriptions
// naturelles.
const ITEMS = [
  // --- Électricité (3) ---
  { service: "electricity", region: "Centre", city: "Yaoundé", neighborhood: "Bastos",
    lat: 3.8920, lng: 11.5180, author: "junior_mballa", conf: 4, agoH: 2,
    desc: "Coupure de courant depuis ce matin, tout le quartier est concerné." },
  { service: "electricity", region: "Littoral", city: "Douala", neighborhood: "Bonabéri",
    lat: 4.0820, lng: 9.6790, author: "estelle_d", conf: 6, agoH: 1,
    desc: "Délestage en cours dans toute la zone." },
  { service: "electricity", region: "Centre", city: "Yaoundé", neighborhood: "Nlongkak",
    lat: 3.8800, lng: 11.5200, author: null, conf: 2, agoH: 0.5,
    desc: "Plus de courant depuis une heure environ." },
  // --- Eau (3) ---
  { service: "water", region: "Littoral", city: "Douala", neighborhood: "Akwa",
    lat: 4.0490, lng: 9.6980, author: "carine_ngo", conf: 3, agoH: 14,
    desc: "Plus d'eau au robinet depuis hier soir." },
  { service: "water", region: "Centre", city: "Yaoundé", neighborhood: "Biyem-Assi",
    lat: 3.8400, lng: 11.4820, author: null, conf: 2, agoH: 5,
    desc: "Coupure d'eau, plus une goutte depuis ce matin." },
  { service: "water", region: "Littoral", city: "Douala", neighborhood: "Makepe",
    lat: 4.0790, lng: 9.7560, author: "brice_mb", conf: 4, agoH: 8,
    desc: "Pression très faible, robinets à sec." },
];

async function run() {
  console.log("→ Suppression de la collection reports (et sous-collections)…");
  await db.recursiveDelete(db.collection("reports"));
  console.log("  reports purgée.");

  console.log(`→ Seed de ${ITEMS.length} coupures réalistes…`);
  const batch = db.batch();
  let n = 1;
  for (const it of ITEMS) {
    const ref = db.collection("reports").doc();
    const reportedAt = Ts.fromMillis(now - it.agoH * HOUR);
    const resolved = it.resolvedAgoH != null;
    batch.set(ref, {
      userId: `seed_${n}`,
      status: resolved ? "resolved" : "ongoing",
      type: "unplanned",
      serviceType: it.service,
      position: { lat: it.lat, lng: it.lng },
      location: { ...CM, region: it.region, city: it.city, neighborhood: it.neighborhood },
      description: it.desc,
      mediaUrl: null,
      authorUsername: it.author, // null = signalement anonyme
      geohash: geohash(it.lat, it.lng),
      confirmationCount: it.conf,
      restorationCount: it.resto || 0,
      reportedAt,
      resolvedAt: resolved ? Ts.fromMillis(now - it.resolvedAgoH * HOUR) : null,
      archivedAt: null,
      createdAt: reportedAt,
      updatedAt: Ts.fromMillis(now - (resolved ? it.resolvedAgoH : it.agoH) * HOUR),
    });
    n++;
  }
  await batch.commit();
  console.log("  Seed terminé ✅");
  process.exit(0);
}

run().catch((e) => { console.error(e); process.exit(1); });
