/**
 * Compte + données de démo pour la REVIEW APPLE (njuka-prod).
 *
 * Les identifiants ci-dessous sont ceux déclarés dans App Store Connect
 * (« Informations de vérification de l'app ») — Apple re-teste CHAQUE mise à
 * jour avec. Si tu changes le mot de passe ici, change-le AUSSI dans ASC.
 *
 * Cycle de vie (règle 2026-08-18, cf. todo.md) :
 *   AVANT chaque soumission Apple :  node seedAppleReview.cjs full
 *     (le reviewer est à Cupertino et la liste est cloisonnée par pays —
 *      sans reports US, l'app lui semble vide)
 *   APRÈS l'approbation :            node seedAppleReview.cjs purge-reports
 *   Le COMPTE ne se purge JAMAIS :   node seedAppleReview.cjs account
 *     (recrée compte + profil + pseudo s'ils manquent, sans toucher au reste)
 */
const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "njuka-prod",
});
const db = admin.firestore();
const Ts = admin.firestore.Timestamp;

const EMAIL = "review@njuka.app";
const PASSWORD = "NjukaReview#2026"; // == déclaration App Store Connect
const USERNAME = "apple_review";

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

const US = { country: "United States", countryCode: "US" };
const HOUR = 3600 * 1000;

const REPORTS = [
  { service: "electricity", city: "Cupertino", neighborhood: "Rancho Rinconada",
    lat: 37.3229, lng: -122.0090, author: "mike_sf", conf: 3, agoH: 1.5,
    desc: "Power went out about an hour ago, whole block is dark." },
  { service: "electricity", city: "Sunnyvale", neighborhood: "Heritage District",
    lat: 37.3688, lng: -122.0363, author: null, conf: 2, agoH: 3,
    desc: "No electricity since this morning, neighbors confirm." },
  { service: "electricity", city: "San Jose", neighborhood: "Willow Glen",
    lat: 37.3069, lng: -121.8900, author: "sarah_j", conf: 5, agoH: 0.5,
    desc: "Outage after the wind picked up, streetlights are off too." },
  { service: "water", city: "Santa Clara", neighborhood: "Old Quad",
    lat: 37.3541, lng: -121.9552, author: "dan_scc", conf: 2, agoH: 6,
    desc: "No water pressure at all since early afternoon." },
  { service: "water", city: "San Francisco", neighborhood: "Mission District",
    lat: 37.7599, lng: -122.4148, author: null, conf: 1, agoH: 10,
    desc: "Water is out on our street, a main may have broken." },
  { service: "electricity", city: "Mountain View", neighborhood: "Old Mountain View",
    lat: 37.3894, lng: -122.0819, author: "lea_mv", conf: 4, agoH: 26, resolvedAgoH: 20,
    desc: "Power cut during the night." },
];

async function ensureAccount() {
  let user;
  try {
    user = await admin.auth().getUserByEmail(EMAIL);
    console.log("Compte review déjà présent:", user.uid);
  } catch (_) {
    user = await admin.auth().createUser({
      email: EMAIL, password: PASSWORD, emailVerified: true,
      displayName: "Apple Review",
    });
    console.log("Compte review créé:", user.uid);
  }
  await db.collection("users").doc(user.uid).set({
    email: EMAIL, username: USERNAME, firstName: "Apple", lastName: "Review",
    birthDate: null, phoneNumber: null, photoURL: null,
    homeLocation: { country: "", countryCode: "", region: "", city: "", neighborhood: "" },
    role: "citizen", status: "active", usernameChangesLeft: 1,
    followedQuartiers: [], disabledAt: null,
    createdAt: Ts.now(), updatedAt: Ts.now(),
  });
  await db.collection("usernames").doc(USERNAME).set({ uid: user.uid, email: EMAIL });
  console.log("Profil + index pseudo posés ✅");
}

async function seedReports() {
  const now = Date.now();
  const batch = db.batch();
  let n = 1;
  for (const it of REPORTS) {
    const ref = db.collection("reports").doc();
    const reportedAt = Ts.fromMillis(now - it.agoH * HOUR);
    const resolved = it.resolvedAgoH != null;
    batch.set(ref, {
      userId: `seed_us_${n++}`,
      status: resolved ? "resolved" : "ongoing",
      type: "unplanned",
      serviceType: it.service,
      position: { lat: it.lat, lng: it.lng },
      location: { ...US, region: "California", city: it.city, neighborhood: it.neighborhood },
      description: it.desc,
      mediaUrl: null,
      authorUsername: it.author,
      geohash: geohash(it.lat, it.lng),
      positionSource: "gps",
      confirmationCount: it.conf,
      restorationCount: resolved ? 3 : 0,
      reportedAt,
      resolvedAt: resolved ? Ts.fromMillis(now - it.resolvedAgoH * HOUR) : null,
      archivedAt: null,
      createdAt: reportedAt,
      updatedAt: Ts.fromMillis(now - (resolved ? it.resolvedAgoH : it.agoH) * HOUR),
    });
  }
  await batch.commit();
  console.log(`${REPORTS.length} reports Bay Area seedés ✅`);
}

async function purgeReports() {
  const snap = await db
    .collection("reports")
    .where("userId", ">=", "seed_us_")
    .where("userId", "<", "seed_us_~")
    .get();
  for (const d of snap.docs) await db.recursiveDelete(d.ref);
  console.log(`${snap.size} reports de démo purgés ✅ (compte review intact)`);
}

const mode = process.argv[2];
(async () => {
  if (mode === "account") await ensureAccount();
  else if (mode === "full") { await ensureAccount(); await seedReports(); }
  else if (mode === "purge-reports") await purgeReports();
  else {
    console.error("Usage: node seedAppleReview.cjs <account|full|purge-reports>");
    process.exit(1);
  }
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
