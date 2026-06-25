/**
 * Seed de données de TEST (Cameroun) : 9 comptes + 9 signalements répartis sur
 * Yaoundé (3), Douala (3) et le Nord (3), chacun par un compte différent.
 *
 * Cible en ligne (staging) : `node functions/scripts/seedCameroon.cjs`
 * Émulateur : préfixer par
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 GCLOUD_PROJECT=lightcutoff-dev
 *
 * Idempotent sur les comptes (réutilise par email) ; ajoute 9 reports à chaque run.
 */
const admin = require("firebase-admin");

const PROJECT = process.env.GCLOUD_PROJECT || "lightcutoff-dev";
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const auth = admin.auth();
const FV = admin.firestore.FieldValue;

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

// pays commun : Cameroun (CM)
const CM = { country: "Cameroun", countryCode: "CM" };

const ITEMS = [
  // --- Yaoundé (région Centre) ---
  { email: "test.yde1@njuka.app", username: "yde_bastos", firstName: "Junior", lastName: "Mballa",
    region: "Centre", city: "Yaoundé", neighborhood: "Bastos", lat: 3.8920, lng: 11.5180,
    description: "Coupure à Bastos (donnée de test)." },
  { email: "test.yde2@njuka.app", username: "yde_biyemassi", firstName: "Carine", lastName: "Ngo",
    region: "Centre", city: "Yaoundé", neighborhood: "Biyem-Assi", lat: 3.8400, lng: 11.4820,
    description: "Coupure à Biyem-Assi (donnée de test)." },
  { email: "test.yde3@njuka.app", username: "yde_centre", firstName: "Patrick", lastName: "Eyenga",
    region: "Centre", city: "Yaoundé", neighborhood: "Mvog-Mbi", lat: 3.8520, lng: 11.5230,
    description: "Coupure à Mvog-Mbi (donnée de test)." },

  // --- Douala (région Littoral) ---
  { email: "test.dla1@njuka.app", username: "dla_akwa", firstName: "Estelle", lastName: "Dipita",
    region: "Littoral", city: "Douala", neighborhood: "Akwa", lat: 4.0490, lng: 9.6980,
    description: "Coupure à Akwa (donnée de test)." },
  { email: "test.dla2@njuka.app", username: "dla_bonaberi", firstName: "Yannick", lastName: "Ewane",
    region: "Littoral", city: "Douala", neighborhood: "Bonabéri", lat: 4.0820, lng: 9.6790,
    description: "Coupure à Bonabéri (donnée de test)." },
  { email: "test.dla3@njuka.app", username: "dla_makepe", firstName: "Brice", lastName: "Mbappe",
    region: "Littoral", city: "Douala", neighborhood: "Makepe", lat: 4.0790, lng: 9.7560,
    description: "Coupure à Makepe (donnée de test)." },

  // --- Nord (Garoua / Maroua / Ngaoundéré) ---
  { email: "test.nord1@njuka.app", username: "nord_garoua", firstName: "Aliou", lastName: "Bello",
    region: "Nord", city: "Garoua", neighborhood: "Garoua", lat: 9.3017, lng: 13.3921,
    description: "Coupure à Garoua (donnée de test)." },
  { email: "test.nord2@njuka.app", username: "nord_maroua", firstName: "Fadimatou", lastName: "Saidou",
    region: "Extrême-Nord", city: "Maroua", neighborhood: "Maroua", lat: 10.5913, lng: 14.3153,
    description: "Coupure à Maroua (donnée de test)." },
  { email: "test.nord3@njuka.app", username: "nord_ngaoundere", firstName: "Ibrahim", lastName: "Aboubakar",
    region: "Adamaoua", city: "Ngaoundéré", neighborhood: "Ngaoundéré", lat: 7.3270, lng: 13.5840,
    description: "Coupure à Ngaoundéré (donnée de test)." },
];

const PASSWORD = "Test1234!";

async function ensureUser(it) {
  let user;
  try {
    user = await auth.getUserByEmail(it.email);
  } catch (_) {
    user = await auth.createUser({
      email: it.email, password: PASSWORD,
      emailVerified: true, displayName: `${it.firstName} ${it.lastName}`,
    });
  }
  const uid = user.uid;
  const uname = it.username.toLowerCase();
  const area = { ...CM, region: it.region, city: it.city, neighborhood: it.neighborhood };
  await db.collection("users").doc(uid).set({
    email: it.email, username: uname,
    firstName: it.firstName, lastName: it.lastName,
    birthDate: null, phoneNumber: null, photoURL: null,
    homeLocation: area, followedQuartiers: [],
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
    location: { ...CM, region: it.region, city: it.city, neighborhood: it.neighborhood },
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
    console.log(`  ✓ @${uname} → ${id} · ${it.city}/${it.neighborhood} [${geohash(it.lat, it.lng)}]`);
  }
  console.log("Terminé : 9 comptes + 9 signalements (Yaoundé, Douala, Nord).");
  process.exit(0);
})().catch((e) => { console.error("Échec:", e); process.exit(1); });
