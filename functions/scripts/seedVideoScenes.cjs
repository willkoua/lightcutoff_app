/**
 * Prépare STAGING (lightcutoff-dev) pour les plans app de la vidéo de
 * lancement (SCRIPT-VIDEO-LANCEMENT.md, séquence 2). Trois modes :
 *
 *   node scripts/seedVideoScenes.cjs map
 *     Purge `reports` puis seede une carte PRÉSENTABLE : belle zone Bastos
 *     (900 m, fraîche → opacité max), taches secondaires élec + eau à
 *     Yaoundé et Douala. Descriptions naturelles, zéro mention de test.
 *     → À relancer juste avant la captation (la fraîcheur pilote l'opacité).
 *
 *   node scripts/seedVideoScenes.cjs wave <lat> <lng> [quartier] [ville]
 *     Plan C (notification + vote 1 tap) : crée un signalement CRÉDIBLE
 *     (défaut : Bastos, Yaoundé) à ~200 m de la position donnée, puis une
 *     confirmation À cette position → `onConfirmationCreated` envoie la
 *     vraie notification (boutons de vote) aux devices à < 500 m.
 *     <lat> <lng> = la POSITION RÉELLE du téléphone de tournage (le device
 *     doit être connecté à un compte, pas anonyme, notifs autorisées).
 *
 *   node scripts/seedVideoScenes.cjs restore <reportId> [votes]
 *     Plan D (retour du courant) : ajoute [votes] (défaut 2) votes de
 *     rétablissement fictifs. Seuil d'auto-résolution = max(3, conf/2) —
 *     avec 2 votes seedés, le tap « C'est revenu » filmé à l'écran est le
 *     3ᵉ et déclenche la résolution + la notif « Le courant est revenu ⚡ ».
 *
 *   node scripts/seedVideoScenes.cjs ping <reportId> [uid]
 *     Envoie IMMÉDIATEMENT la notification « Le courant est-il revenu ? »
 *     ([Toujours coupé] [C'est revenu ✓]) — même payload que le cron
 *     `reportLifecycle`, sans attendre les 4 h. Sans [uid] : cible tous les
 *     devices actifs depuis < 12 h. Rejouable à volonté entre les prises.
 *
 *   node scripts/seedVideoScenes.cjs wave auto  (variante du mode wave)
 *     Prend comme position le device le plus récemment enregistré qui a une
 *     position — pratique : connecte-toi sur le téléphone, notifs ON, et la
 *     vague part « près de toi » sans chercher tes coordonnées.
 *
 * (ADC gcloud requis, comme cleanAndSeedStaging.cjs.)
 */
const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "lightcutoff-dev",
});
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

const CM = { country: "Cameroun", countryCode: "CM" };
const HOUR = 3600 * 1000;

// Carte « belle » : Bastos = la zone vedette (900 m, fraîche, 7 confirmations).
// Les autres donnent de la texture sans voler la vedette. Mix élec (ambre) /
// eau (bleu ciel) pour la richesse visuelle.
const MAP_ITEMS = [
  { service: "electricity", region: "Centre", city: "Yaoundé", neighborhood: "Bastos",
    lat: 3.8920, lng: 11.5180, author: "junior_mballa", conf: 7, agoH: 0.75, radiusM: 900,
    desc: "Coupure de courant, tout le quartier est touché." },
  { service: "electricity", region: "Centre", city: "Yaoundé", neighborhood: "Nlongkak",
    lat: 3.8800, lng: 11.5200, author: null, conf: 3, agoH: 1.5, radiusM: 420,
    desc: "Plus de courant depuis un moment." },
  { service: "electricity", region: "Centre", city: "Yaoundé", neighborhood: "Etoa-Meki",
    lat: 3.8763, lng: 11.5306, author: "sandrine_e", conf: 2, agoH: 3, radiusM: 260,
    desc: "Le courant est parti d'un coup, quelqu'un d'autre ?" },
  { service: "water", region: "Centre", city: "Yaoundé", neighborhood: "Biyem-Assi",
    lat: 3.8400, lng: 11.4820, author: "carine_ngo", conf: 4, agoH: 2, radiusM: 520,
    desc: "Plus d'eau au robinet depuis ce matin." },
  { service: "electricity", region: "Littoral", city: "Douala", neighborhood: "Bonabéri",
    lat: 4.0820, lng: 9.6790, author: "estelle_d", conf: 6, agoH: 1, radiusM: 700,
    desc: "Délestage en cours dans toute la zone." },
  { service: "water", region: "Littoral", city: "Douala", neighborhood: "Akwa",
    lat: 4.0490, lng: 9.6980, author: null, conf: 3, agoH: 4, radiusM: 380,
    desc: "Coupure d'eau, plus une goutte." },
];

function reportDoc(it, now) {
  const reportedAt = Ts.fromMillis(now - it.agoH * HOUR);
  return {
    userId: `seed_${it.neighborhood.toLowerCase().replace(/[^a-z]/g, "")}`,
    status: "ongoing",
    type: "unplanned",
    serviceType: it.service,
    position: { lat: it.lat, lng: it.lng },
    location: { ...CM, region: it.region, city: it.city, neighborhood: it.neighborhood },
    description: it.desc,
    mediaUrl: null,
    authorUsername: it.author,
    geohash: geohash(it.lat, it.lng),
    confirmationCount: it.conf,
    restorationCount: 0,
    impactRadiusM: it.radiusM,
    reportedAt,
    resolvedAt: null,
    archivedAt: null,
    createdAt: reportedAt,
    // updatedAt récent = opacité de zone maximale (fraîcheur < 2 h).
    updatedAt: Ts.fromMillis(now - Math.min(it.agoH, 0.5) * HOUR),
  };
}

async function seedMap() {
  const now = Date.now();
  console.log("→ Purge de `reports` (staging)…");
  await db.recursiveDelete(db.collection("reports"));
  console.log(`→ Seed de ${MAP_ITEMS.length} coupures « vidéo »…`);
  const batch = db.batch();
  for (const it of MAP_ITEMS) batch.set(db.collection("reports").doc(), reportDoc(it, now));
  await batch.commit();
  console.log("  Carte prête ✅ (Bastos 900 m = la zone vedette).");
  console.log("  ⚠️ Relancer ce mode juste avant la captation : la fraîcheur pilote l'opacité.");
}

async function wave(lat, lng, quartier = "Bastos", ville = "Yaoundé") {
  const devices = await db.collection("devices").get();
  let targetable = 0;
  const distM = (a, b) => {
    const R = 6371000, rad = (d) => (d * Math.PI) / 180;
    const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
    const h = Math.sin(dLat / 2) ** 2 +
      Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  };
  devices.docs.forEach((d) => {
    const data = d.data();
    if (!data.position) return;
    const dist = Math.round(distM({ lat, lng }, data.position));
    if (dist <= 500) {
      targetable++;
      console.log(`  device ${d.id.slice(0, 12)}… à ${dist} m · fcmEnabled=${data.fcmEnabled !== false}`);
    }
  });
  console.log(`Devices ciblables (<500 m) : ${targetable}`);
  if (targetable === 0) {
    console.warn("⚠️ Aucun device ciblable — connecte un COMPTE (pas anonyme) sur le téléphone, notifs ON, puis relance.");
  }

  const rLat = lat + 0.0018, rLng = lng; // ~200 m au nord
  const now = Date.now();
  const region = ville === "Douala" ? "Littoral" : "Centre";
  const ref = await db.collection("reports").add({
    userId: "seed_video_author",
    status: "ongoing",
    type: "unplanned",
    serviceType: "electricity",
    position: { lat: rLat, lng: rLng },
    location: { ...CM, region, city: ville, neighborhood: quartier },
    description: "Coupure de courant, est-ce que c'est tout le quartier ?",
    mediaUrl: null,
    authorUsername: "junior_mballa",
    geohash: geohash(rLat, rLng),
    confirmationCount: 1,
    restorationCount: 0,
    impactRadiusM: 300,
    reportedAt: Ts.fromMillis(now - 12 * 60 * 1000),
    resolvedAt: null,
    archivedAt: null,
    createdAt: Ts.fromMillis(now - 12 * 60 * 1000),
    updatedAt: Ts.fromMillis(now),
  });
  console.log(`Report vidéo créé : ${ref.id} (${quartier}, ${ville})`);

  await ref.collection("confirmations").doc("seed_video_confirmer").set({
    createdAt: Ts.fromMillis(now),
    geohash: geohash(lat, lng),
    position: { lat, lng },
  });
  console.log("Confirmation posée → la vague part (notification avec boutons sous ~10 s).");
  console.log(`Plan D ensuite : node scripts/seedVideoScenes.cjs restore ${ref.id}`);
}

async function restore(reportId, votes = 2) {
  const ref = db.collection("reports").doc(reportId);
  const snap = await ref.get();
  if (!snap.exists) { console.error(`Report ${reportId} introuvable.`); process.exit(1); }
  const r = snap.data();
  const now = Date.now();
  const base = r.position || { lat: 0, lng: 0 };
  const batch = db.batch();
  for (let i = 0; i < votes; i++) {
    const p = { lat: base.lat + 0.0007 * (i + 1), lng: base.lng - 0.0005 * (i + 1) };
    batch.set(ref.collection("restorations").doc(`seed_video_restorer_${i + 1}`), {
      createdAt: Ts.fromMillis(now + i),
      geohash: geohash(p.lat, p.lng),
      position: p,
    });
  }
  batch.update(ref, {
    restorationCount: admin.firestore.FieldValue.increment(votes),
    updatedAt: Ts.fromMillis(now),
  });
  await batch.commit();
  const total = (r.restorationCount || 0) + votes;
  const threshold = Math.max(3, Math.ceil((r.confirmationCount || 0) * 0.5));
  console.log(`${votes} vote(s) seedé(s) → restorationCount=${total} (seuil de résolution : ${threshold}).`);
  if (total >= threshold) {
    console.log("Seuil atteint : la résolution + la notif « revenu » partent maintenant.");
  } else {
    console.log(`Il manque ${threshold - total} vote(s) : le tap « C'est revenu » filmé déclenchera la résolution.`);
  }
}

/** Device le plus récent ayant une position (repère « près de moi »). */
async function freshestDeviceWithPosition() {
  const snap = await db.collection("devices").get();
  let best = null;
  snap.docs.forEach((d) => {
    const x = d.data();
    if (!x.position) return;
    const t = x.updatedAt && x.updatedAt.toMillis ? x.updatedAt.toMillis() : 0;
    if (!best || t > best.t) best = { t, pos: x.position, userId: x.userId, token: d.id };
  });
  return best;
}

/** Envoie la notif « revenu ? » (même payload data-only que reportLifecycle). */
async function ping(reportId, uid) {
  const snap = await db.collection("reports").doc(reportId).get();
  if (!snap.exists) { console.error(`Report ${reportId} introuvable.`); process.exit(1); }
  const r = snap.data();

  const devices = await db.collection("devices").get();
  const cutoff = Date.now() - 12 * 3600 * 1000;
  const tokens = [];
  devices.docs.forEach((d) => {
    const x = d.data();
    if (x.fcmEnabled === false) return;
    if (uid) { if (x.userId === uid) tokens.push(d.id); return; }
    const t = x.updatedAt && x.updatedAt.toMillis ? x.updatedAt.toMillis() : 0;
    if (t >= cutoff) tokens.push(d.id);
  });
  if (tokens.length === 0) {
    console.error(uid
      ? `Aucun device pour uid=${uid}.`
      : "Aucun device actif < 12 h. Connecte un compte sur le téléphone (notifs ON) puis relance.");
    process.exit(1);
  }

  const isWater = r.serviceType === "water";
  const data = {
    reportId,
    kind: "still_out_ping",
    serviceType: r.serviceType || "electricity",
    title: isWater ? "L'eau est-elle revenue ? 💧" : "Le courant est-il revenu ? ⚡",
    body: "Dis-le à tes voisins en un geste : toujours coupé, ou c'est revenu ?",
  };
  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    data,
    android: { priority: "high" },
    apns: {
      headers: { "apns-push-type": "alert", "apns-priority": "10" },
      payload: { aps: { alert: { title: data.title, body: data.body }, sound: "default" } },
    },
  });
  console.log(`Ping envoyé : ${res.successCount} OK / ${res.failureCount} échec(s) sur ${tokens.length} device(s).`);
  console.log("Sur le téléphone : [Toujours coupé] [C'est revenu ✓] — rejouable à volonté.");
}

(async () => {
  const [mode, a, b, c, d] = process.argv.slice(2);
  if (mode === "map") await seedMap();
  else if (mode === "wave") {
    if (a === "auto") {
      const best = await freshestDeviceWithPosition();
      if (!best) {
        console.error("Aucun device avec position. Connecte un compte sur le téléphone (notifs ON) puis relance.");
        process.exit(1);
      }
      const age = Math.round((Date.now() - best.t) / 60000);
      console.log(`Device repère : uid=${(best.userId || "?").slice(0, 10)}… (maj il y a ${age} min).`);
      await wave(best.pos.lat, best.pos.lng, b || "Bastos", c || "Yaoundé");
    } else {
      const lat = parseFloat(a), lng = parseFloat(b);
      if (Number.isNaN(lat) || Number.isNaN(lng)) {
        console.error("Usage: node scripts/seedVideoScenes.cjs wave <lat> <lng> [quartier] [ville] | wave auto [quartier] [ville]");
        process.exit(1);
      }
      await wave(lat, lng, c || "Bastos", d || "Yaoundé");
    }
  } else if (mode === "restore") {
    if (!a) { console.error("Usage: node scripts/seedVideoScenes.cjs restore <reportId> [votes]"); process.exit(1); }
    await restore(a, b ? parseInt(b, 10) : 2);
  } else if (mode === "ping") {
    if (!a) { console.error("Usage: node scripts/seedVideoScenes.cjs ping <reportId> [uid]"); process.exit(1); }
    await ping(a, b);
  } else {
    console.error("Modes : map | wave <lat> <lng>|auto [quartier] [ville] | restore <reportId> [votes] | ping <reportId> [uid]");
    process.exit(1);
  }
  process.exit(0);
})().catch((e) => { console.error("Échec :", e); process.exit(1); });
