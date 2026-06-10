/**
 * Seed manuel des coupures officielles Eneo dans l'émulateur Firestore.
 *
 * Lance l'ingestion (`runEneoIngestion`) en **appel direct** — on contourne le
 * déclencheur HTTP, car le worker HTTPS de l'émulateur firebase-tools plante
 * avec firebase-functions v7. Le `fetch` interroge le vrai endpoint Eneo ; les
 * écritures vont dans l'émulateur (FIRESTORE_EMULATOR_HOST injecté par
 * `firebase emulators:exec`).
 *
 * Usage (depuis lightcutoff_app/, Node 22) :
 *   export PATH="$HOME/.nvm/versions/node/v22.11.0/bin:$PATH"
 *   (cd functions && npm run build)
 *   firebase emulators:exec --only firestore --project lightcutoff-dev \
 *     "node functions/scripts/seedEneo.cjs"
 */
const admin = require("firebase-admin");
const { runEneoIngestion } = require("../lib/index.js");

(async () => {
  const res = await runEneoIngestion();
  console.log("Ingestion:", JSON.stringify(res));

  const db = admin.firestore();
  const all = await db.collection("official_outages").get();
  const vides = all.docs.filter((d) => !d.data().quartier).length;
  console.log(`Docs écrits: ${all.size} · quartiers vides: ${vides}`);

  for (const d of all.docs.slice(0, 3)) {
    const x = d.data();
    console.log(
      `  ex: ${x.region} | ${JSON.stringify(x.quartier)} | ${x.progDate} | ` +
        `${x.startsAt && x.startsAt.toDate().toISOString()}`
    );
  }
  process.exit(0);
})().catch((e) => {
  console.error("seedEneo KO:", (e && e.stack) || e);
  process.exit(1);
});
