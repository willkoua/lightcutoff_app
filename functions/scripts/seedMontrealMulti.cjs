/**
 * Seed ADDITIF : 3 coupures d'électricité + 3 coupures d'eau à Montréal (CA).
 *
 * N'efface RIEN — ajoute 6 signalements (id auto) aux données existantes.
 * Style « seed_ » (pas de comptes Auth créés), comme cleanAndSeedStaging.cjs.
 *
 * Cible en ligne (staging lightcutoff-dev) :
 *   node functions/scripts/seedMontrealMulti.cjs
 *   (Application Default Credentials — `gcloud auth application-default login`,
 *    Node 20 via nvm.)
 * Émulateur :
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=lightcutoff-dev \
 *     node functions/scripts/seedMontrealMulti.cjs
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

const CA = { country: "Canada", countryCode: "CA", region: "Québec", city: "Montréal" };
const HOUR = 3600 * 1000;
const now = Date.now();

// 3 électricité + 3 eau, quartiers réels de Montréal, descriptions naturelles.
const ITEMS = [
  // --- Électricité (3) ---
  { service: "electricity", neighborhood: "Ville-Marie",
    lat: 45.5017, lng: -73.5673, author: "alex_mtl", conf: 5, agoH: 2,
    desc: "Panne de courant au centre-ville depuis ce matin, tout le pâté est touché." },
  { service: "electricity", neighborhood: "Le Plateau-Mont-Royal",
    lat: 45.5230, lng: -73.5800, author: null, conf: 3, agoH: 1,
    desc: "Plus d'électricité sur le Plateau depuis environ une heure." },
  { service: "electricity", neighborhood: "Rosemont–La Petite-Patrie",
    lat: 45.5400, lng: -73.5900, author: "sam_g", conf: 4, agoH: 0.5,
    desc: "Coupure de courant, les feux de circulation sont éteints." },
  // --- Eau (3) ---
  { service: "water", neighborhood: "Verdun",
    lat: 45.4583, lng: -73.5680, author: "jo_roy", conf: 4, agoH: 6,
    desc: "Plus d'eau au robinet depuis ce matin, avis probablement lié à des travaux." },
  { service: "water", neighborhood: "Hochelaga-Maisonneuve",
    lat: 45.5500, lng: -73.5400, author: null, conf: 2, agoH: 3,
    desc: "Coupure d'eau dans le secteur, pression nulle." },
  { service: "water", neighborhood: "Côte-des-Neiges",
    lat: 45.4960, lng: -73.6200, author: "lea_cdn", conf: 3, agoH: 9,
    desc: "Eau coupée depuis hier soir, rien qui coule." },
];

(async () => {
  const target = process.env.FIRESTORE_EMULATOR_HOST ? "ÉMULATEUR" : "EN LIGNE";
  console.log(`Projet=${PROJECT} · cible=${target} · +${ITEMS.length} signalements Montréal`);
  const batch = db.batch();
  let n = 1;
  for (const it of ITEMS) {
    const ref = db.collection("reports").doc();
    const reportedAt = Ts.fromMillis(now - it.agoH * HOUR);
    batch.set(ref, {
      userId: `seed_mtl_${n}`,
      status: "ongoing",
      type: "unplanned",
      serviceType: it.service,
      position: { lat: it.lat, lng: it.lng },
      location: { ...CA, neighborhood: it.neighborhood },
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
