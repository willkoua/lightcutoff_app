// Script ponctuel : renseigne location.countryCode (ISO) sur les reports qui ne
// l'ont pas, à partir de location.country (nom). Nécessaire pour le
// cloisonnement strict par pays (les anciens reports n'avaient pas le code ISO).
// Usage : node functions/scripts/backfillCountryCode.cjs   (ADC requis)
const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "lightcutoff-dev",
});

// Nom de pays (FR/EN, minuscules) → code ISO. Couvre les données présentes +
// pays probables de la cible. Étendre au besoin.
const NAME_TO_ISO = {
  cameroun: "CM", cameroon: "CM",
  canada: "CA",
  kenya: "KE",
  france: "FR",
  nigeria: "NG", nigéria: "NG",
  "côte d'ivoire": "CI", "cote d'ivoire": "CI", "ivory coast": "CI",
  sénégal: "SN", senegal: "SN",
  gabon: "GA",
  tchad: "TD", chad: "TD",
  "république centrafricaine": "CF", "central african republic": "CF",
  "guinée équatoriale": "GQ", "equatorial guinea": "GQ",
  "états-unis": "US", "united states": "US", usa: "US",
};

(async () => {
  const snap = await admin.firestore().collection("reports").get();
  let updated = 0, already = 0, unresolved = 0;
  const unknown = {};
  for (const doc of snap.docs) {
    const x = doc.data();
    const loc = x.location || {};
    if (loc.countryCode) { already++; continue; }
    const name = (loc.country || "").trim().toLowerCase();
    const iso = NAME_TO_ISO[name];
    if (!iso) {
      unresolved++;
      if (name) unknown[name] = (unknown[name] || 0) + 1;
      continue;
    }
    await doc.ref.update({ "location.countryCode": iso });
    updated++;
  }
  console.log(`maj: ${updated} · déjà ok: ${already} · non résolus: ${unresolved}`);
  if (Object.keys(unknown).length) {
    console.log("noms inconnus (à ajouter au mapping):", JSON.stringify(unknown));
  }
  process.exit(0);
})().catch((e) => { console.error("ERR:", e.message); process.exit(1); });
