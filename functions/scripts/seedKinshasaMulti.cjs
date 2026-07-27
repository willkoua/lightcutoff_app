/**
 * Seed ADDITIF : 3 coupures d'électricité + 3 coupures d'eau à Kinshasa (CD).
 *
 * N'efface RIEN — ajoute 6 signalements (id auto) aux données existantes.
 * Style « seed_ » (pas de comptes Auth créés), comme cleanAndSeedStaging.cjs.
 *
 * Cible en ligne (staging lightcutoff-dev) :
 *   node functions/scripts/seedKinshasaMulti.cjs
 *   (Application Default Credentials — `gcloud auth application-default login`.)
 * Émulateur :
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=lightcutoff-dev \
 *     node functions/scripts/seedKinshasaMulti.cjs
 */
const admin = require("firebase-admin");

const PROJECT = process.env.GCLOUD_PROJECT || "lightcutoff-dev";
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const Ts = admin.firestore.Timestamp;

// --- geohash (précision 6) — même algo que lib/utils/geohash.dart ---
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

const CD = { country: "RD Congo", countryCode: "CD", region: "Kinshasa", city: "Kinshasa" };
const HOUR = 3600 * 1000;
const now = Date.now();

// 3 électricité + 3 eau, communes réelles de Kinshasa, descriptions naturelles.
const ITEMS = [
  // --- Électricité (3) ---
  { service: "electricity", neighborhood: "Gombe",
    lat: -4.3033, lng: 15.3050, author: "patrick_kin", conf: 6, agoH: 2,
    desc: "Délestage à la Gombe depuis ce matin, tout le quartier est dans le noir." },
  { service: "electricity", neighborhood: "Limete",
    lat: -4.3500, lng: 15.3400, author: null, conf: 4, agoH: 1,
    desc: "Plus de courant à Limete depuis environ une heure." },
  { service: "electricity", neighborhood: "Ngaliema",
    lat: -4.3700, lng: 15.2600, author: "grace_ng", conf: 3, agoH: 0.5,
    desc: "Coupure d'électricité, le transformateur du coin a sauté." },
  // --- Eau (3) ---
  { service: "water", neighborhood: "Masina",
    lat: -4.3900, lng: 15.4100, author: "josue_mas", conf: 5, agoH: 8,
    desc: "Pas d'eau au robinet depuis hier soir dans tout le secteur." },
  { service: "water", neighborhood: "Lemba",
    lat: -4.4000, lng: 15.3200, author: null, conf: 2, agoH: 4,
    desc: "Coupure d'eau à Lemba, plus rien qui coule depuis ce matin." },
  { service: "water", neighborhood: "Kalamu",
    lat: -4.3550, lng: 15.3050, author: "nadege_kal", conf: 3, agoH: 12,
    desc: "Pression très faible, les robinets sont à sec depuis la nuit." },
];

(async () => {
  const target = process.env.FIRESTORE_EMULATOR_HOST ? "ÉMULATEUR" : "EN LIGNE";
  console.log(`Projet=${PROJECT} · cible=${target} · +${ITEMS.length} signalements Kinshasa`);
  const batch = db.batch();
  let n = 1;
  for (const it of ITEMS) {
    const ref = db.collection("reports").doc();
    const reportedAt = Ts.fromMillis(now - it.agoH * HOUR);
    batch.set(ref, {
      userId: `seed_kin_${n}`,
      status: "ongoing",
      type: "unplanned",
      serviceType: it.service,
      position: { lat: it.lat, lng: it.lng },
      location: { ...CD, neighborhood: it.neighborhood },
      description: it.desc,
      mediaUrl: null,
      authorUsername: it.author, // null = signalement anonyme
      geohash: geohash(it.lat, it.lng),
      confirmationCount: it.conf,
      restorationCount: 0,
      reportedAt,
      resolvedAt: null,
      archivedAt: null,
      createdAt: reportedAt,
      updatedAt: reportedAt,
    });
    console.log(`  + ${it.service.padEnd(11)} · ${it.neighborhood} [${geohash(it.lat, it.lng)}]`);
    n++;
  }
  await batch.commit();
  console.log("Terminé ✅ (6 signalements ajoutés, rien effacé).");
  process.exit(0);
})().catch((e) => { console.error("Échec:", e); process.exit(1); });
