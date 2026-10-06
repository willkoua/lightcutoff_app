/**
 * Lance l'ingestion KPLC (Kenya) en **appel direct** contre le Firestore EN
 * LIGNE du projet choisi — sert à amorcer/vérifier la donnée sans attendre le
 * cron `ingestKplcOutages`. Le `fetch` interroge le vrai site KPLC ; les
 * écritures vont dans `official_outages/` du projet.
 *
 * Usage (depuis lightcutoff_app/, Node 22, ADC configurées) :
 *   (cd functions && npm run build)
 *   GCLOUD_PROJECT=lightcutoff-dev node functions/scripts/runKplc.cjs
 *   GCLOUD_PROJECT=njuka-prod     node functions/scripts/runKplc.cjs
 */
const project = process.env.GCLOUD_PROJECT;
if (!["lightcutoff-dev", "njuka-prod"].includes(project)) {
  console.error(
    "Définis GCLOUD_PROJECT=lightcutoff-dev|njuka-prod avant de lancer."
  );
  process.exit(1);
}
const admin = require("firebase-admin");
const { runKplcIngestion } = require("../lib/index.js");

(async () => {
  const res = await runKplcIngestion();
  console.log(`Ingestion KPLC (${project}):`, JSON.stringify(res));

  const db = admin.firestore();
  const snap = await db
    .collection("official_outages")
    .where("provider", "==", "kplc")
    .get();
  const vides = snap.docs.filter((d) => !d.data().quartier).length;
  console.log(`Docs KPLC en base: ${snap.size} · quartiers vides: ${vides}`);
  for (const d of snap.docs.slice(0, 3)) {
    const x = d.data();
    console.log(
      `  ex: ${x.region} | ${x.ville} | ${JSON.stringify(x.quartier)} | ` +
        `${x.progDate} ${x.startTime}→${x.endTime}`
    );
  }
  process.exit(0);
})().catch((e) => {
  console.error("runKplc KO:", (e && e.stack) || e);
  process.exit(1);
});
