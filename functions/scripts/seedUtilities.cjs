/**
 * Seed/MAJ du catalogue `utilities` (source de vérité des compagnies élec/eau
 * depuis le 2026-08-13 — l'app embarque un filet Cameroun, le remote prime).
 *
 * Lancer : node functions/scripts/seedUtilities.cjs <lightcutoff-dev|njuka-prod>
 *
 * Ajouter un pays = ajouter une entrée ici puis relancer (aucune release app).
 * `enabled: false` retire une compagnie du catalogue actif (y compris une
 * compagnie embarquée dans l'app).
 */
const admin = require("firebase-admin");

const project = process.argv[2];
if (!["lightcutoff-dev", "njuka-prod"].includes(project)) {
  console.error("Usage: node seedUtilities.cjs <lightcutoff-dev|njuka-prod>");
  process.exit(1);
}
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: project,
});
const db = admin.firestore();

/** id = clé du doc, alignée sur `provider` des official_outages. */
const UTILITIES = {
  // ⚠️ `scheduledOutages` DOIT figurer ici : le catalogue remote surcharge le
  // filet embarqué par `id` (lib/config/utilities.dart). Un doc sans le champ
  // écraserait le `true` embarqué d'eneo → onglet « Programmées » masqué au
  // Cameroun. true seulement là où une source d'ingestion existe.
  eneo: {
    service: "electricity",
    country: "CM",
    label: "SOCADEL", // renommage commercial Eneo → SOCADEL (id conservé)
    countryLabel: "Cameroun",
    countryAliases: ["cameroun", "cameroon"],
    scheduledOutages: true, // cron ingestEneoOutages
    enabled: true,
  },
  camwater: {
    service: "water",
    country: "CM",
    label: "CAMWATER",
    countryLabel: "Cameroun",
    countryAliases: ["cameroun", "cameroon"],
    scheduledOutages: false,
    enabled: true,
  },
  cie: {
    service: "electricity",
    country: "CI",
    label: "CIE",
    countryLabel: "Côte d'Ivoire",
    countryAliases: ["côte d'ivoire", "cote d'ivoire", "ivory coast"],
    scheduledOutages: false,
    enabled: true,
  },
  sodeci: {
    service: "water",
    country: "CI",
    label: "SODECI",
    countryLabel: "Côte d'Ivoire",
    countryAliases: ["côte d'ivoire", "cote d'ivoire", "ivory coast"],
    scheduledOutages: false,
    enabled: true,
  },
  // Kenya Power (élec). scheduledOutages:true → onglet « Programmées » actif,
  // alimenté par le cron ingestKplcOutages (PDF KPLC scrapés). Pas de source
  // d'eau publique au Kenya à ce jour.
  kplc: {
    service: "electricity",
    country: "KE",
    label: "Kenya Power",
    countryLabel: "Kenya",
    countryAliases: ["kenya"],
    scheduledOutages: true,
    enabled: true,
  },
};

async function run() {
  const batch = db.batch();
  for (const [id, data] of Object.entries(UTILITIES)) {
    batch.set(db.collection("utilities").doc(id), {
      ...data,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  console.log(
    `${Object.keys(UTILITIES).length} utilities seedées sur ${project} ✅`,
  );
  process.exit(0);
}
run().catch((e) => { console.error(e); process.exit(1); });
