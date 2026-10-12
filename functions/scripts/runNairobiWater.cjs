/**
 * Lance l'ingestion Nairobi Water (Kenya, eau) en appel direct contre le
 * Firestore EN LIGNE du projet choisi — amorce/vérifie la donnée sans attendre
 * le cron. Le `fetch` interroge l'API WordPress + les PDF du vrai site.
 *
 * Usage (depuis lightcutoff_app/, Node 22, ADC configurées) :
 *   (cd functions && npm run build)
 *   GCLOUD_PROJECT=lightcutoff-dev node functions/scripts/runNairobiWater.cjs
 *   GCLOUD_PROJECT=njuka-prod     node functions/scripts/runNairobiWater.cjs
 */
const project = process.env.GCLOUD_PROJECT;
if (!["lightcutoff-dev", "njuka-prod"].includes(project)) {
  console.error(
    "Définis GCLOUD_PROJECT=lightcutoff-dev|njuka-prod avant de lancer."
  );
  process.exit(1);
}
const admin = require("firebase-admin");
const { runNairobiWaterIngestion } = require("../lib/index.js");

(async () => {
  const res = await runNairobiWaterIngestion();
  console.log(`Ingestion Nairobi Water (${project}):`, JSON.stringify(res));

  const db = admin.firestore();
  const snap = await db
    .collection("official_outages")
    .where("provider", "==", "nairobi_water")
    .get();
  console.log(`Docs eau en base: ${snap.size}`);
  for (const d of snap.docs.slice(0, 4)) {
    const x = d.data();
    console.log(
      `  ex: ${x.quartier} | ${x.serviceType} | ${x.progDate} ` +
        `${x.startTime}→${x.endTime}`
    );
  }
  process.exit(0);
})().catch((e) => {
  console.error("runNairobiWater KO:", (e && e.stack) || e);
  process.exit(1);
});
