# Tests manuels (smoke tests)

## Ingestion Eneo — écriture émulateur bout-en-bout (V1 backend) ✅

> Vérifie l'écriture réelle dans Firestore (`official_outages/`), la déduplication et la purge.
> On lance l'ingestion en **appel direct** via un script (`functions/scripts/seedEneo.cjs`), **pas**
> via un déclencheur HTTP : le worker HTTPS de l'émulateur firebase-tools plante avec
> firebase-functions v7 (« functions.config() removed » → « Failed to load function »). Le cron de
> prod `ingestEneoOutages` n'est pas concerné.

### Recette rapide (headless)
```bash
cd ~/Desktop/Projets/lightcutoff/lightcutoff_app
(cd functions && npm run build)
firebase emulators:exec --only firestore --project lightcutoff-dev \
  "node functions/scripts/seedEneo.cjs"
```
Sortie attendue (le `fetch` appelle le vrai Eneo → nécessite internet) :
```
Ingestion: {"upserted":~650,"pruned":0}
Docs écrits: ~650 · quartiers vides: 0
  ex: EST | "BIRPONDO" | 2026-06-13 | 2026-06-13T18:00:00.000Z
```
- [ ] `upserted` ≈ volume du jour, `pruned` cohérent
- [ ] **0 quartier vide**
- [ ] horaires en UTC corrects (06:00 Douala → 05:00Z, etc.)

> ℹ️ Tourne avec le **Node par défaut** (v24) — pas besoin de basculer en Node 22.

### Variante visuelle (inspecter dans l'UI émulateur)
Terminal A :
```bash
cd ~/Desktop/Projets/lightcutoff/lightcutoff_app
(cd functions && npm run build)
firebase emulators:start --only firestore
```
Terminal B (pointer le script vers l'émulateur en cours) :
```bash
cd ~/Desktop/Projets/lightcutoff/lightcutoff_app
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=lightcutoff-dev \
  node functions/scripts/seedEneo.cjs
```
Puis **http://127.0.0.1:4000** → Firestore → collection `official_outages` :
- [ ] ~650 docs, champs `provider/country/region/quartier/progDate/startsAt/endsAt/fetchedAt`
- [ ] relancer le script → le nombre **ne double pas** (idempotence par `rawHash`)

### Notes / pièges
- `npm test` (functions) doit tourner sous le **Node par défaut** : sous un Node forcé via nvm,
  `tsx`/esbuild peut planter (mismatch de binaire) — faux positif, pas une vraie erreur de test.
- `pruned > 0` est normal une fois que des dates Eneo passent (purge des entrées < aujourd'hui).
