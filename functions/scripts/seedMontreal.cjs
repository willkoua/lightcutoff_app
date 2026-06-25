/**
 * Seed de données de TEST : 3 comptes + 3 signalements répartis dans Montréal.
 *
 * Cible :
 *   - En ligne (staging lightcutoff-dev) : `node functions/scripts/seedMontreal.cjs`
 *     (utilise les Application Default Credentials — `firebase login` / gcloud).
 *   - Émulateur :
 *     `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
 *        GCLOUD_PROJECT=lightcutoff-dev node functions/scripts/seedMontreal.cjs`
 *
 * Idempotent : relancer ne duplique pas les comptes (réutilise par email) ; en
 * revanche chaque exécution ajoute 3 nouveaux signalements (id auto).
 */
const admin = require("firebase-admin");

const PROJECT = process.env.GCLOUD_PROJECT || "lightcutoff-dev";
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const auth = admin.auth();
const FV = admin.firestore.FieldValue;

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

const AREA = { country: "Canada", countryCode: "CA", region: "Québec", city: "Montréal" };

// 3 comptes + leur signalement, répartis dans Montréal.
const ITEMS = [
  {
    email: "test.mtl1@njuka.app", password: "Test1234!",
    username: "mtl_centre", firstName: "Alex", lastName: "Tremblay",
    lat: 45.5017, lng: -73.5673, neighborhood: "Ville-Marie",
    description: "Coupure au centre-ville (donnée de test).",
  },
  {
    email: "test.mtl2@njuka.app", password: "Test1234!",
    username: "mtl_plateau", firstName: "Sam", lastName: "Gagnon",
    lat: 45.5230, lng: -73.5800, neighborhood: "Le Plateau-Mont-Royal",
    description: "Coupure sur le Plateau (donnée de test).",
  },
  {
    email: "test.mtl3@njuka.app", password: "Test1234!",
    username: "mtl_verdun", firstName: "Jo", lastName: "Roy",
    lat: 45.4583, lng: -73.5680, neighborhood: "Verdun",
    description: "Coupure à Verdun (donnée de test).",
  },
];

async function ensureUser(it) {
  let user;
  try {
    user = await auth.getUserByEmail(it.email);
  } catch (_) {
    user = await auth.createUser({
      email: it.email, password: it.password,
      emailVerified: true, displayName: `${it.firstName} ${it.lastName}`,
    });
  }
  const uid = user.uid;
  const uname = it.username.toLowerCase();
  const home = { ...AREA, neighborhood: it.neighborhood };
  await db.collection("users").doc(uid).set({
    email: it.email, username: uname,
    firstName: it.firstName, lastName: it.lastName,
    birthDate: null, phoneNumber: null, photoURL: null,
    homeLocation: home, followedQuartiers: [],
    role: "citizen", status: "active", disabledAt: null,
    createdAt: FV.serverTimestamp(), updatedAt: FV.serverTimestamp(),
  }, { merge: true });
  await db.collection("usernames").doc(uname).set({ uid, email: it.email });
  return { uid, uname };
}

async function createReport(it, uid, uname) {
  const ref = await db.collection("reports").add({
    userId: uid,
    status: "ongoing",
    type: "unplanned",
    position: { lat: it.lat, lng: it.lng },
    location: { ...AREA, neighborhood: it.neighborhood },
    description: it.description,
    mediaUrl: null,
    authorUsername: uname,
    geohash: geohash(it.lat, it.lng),
    confirmationCount: 0,
    restorationCount: 0,
    reportedAt: FV.serverTimestamp(),
    resolvedAt: null,
    archivedAt: null,
    createdAt: FV.serverTimestamp(),
    updatedAt: FV.serverTimestamp(),
  });
  return ref.id;
}

(async () => {
  const target = process.env.FIRESTORE_EMULATOR_HOST ? "ÉMULATEUR" : "EN LIGNE";
  console.log(`Projet=${PROJECT} · cible=${target}`);
  for (const it of ITEMS) {
    const { uid, uname } = await ensureUser(it);
    const id = await createReport(it, uid, uname);
    console.log(`  ✓ @${uname} (${uid.slice(0, 6)}…) → report ${id} · ${it.neighborhood} [${geohash(it.lat, it.lng)}]`);
  }
  console.log("Terminé : 3 comptes + 3 signalements.");
  process.exit(0);
})().catch((e) => { console.error("Échec:", e); process.exit(1); });
