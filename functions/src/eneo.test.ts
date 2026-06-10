import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeEneo, RawEneoItem } from "./sources/eneo";

/** Échantillon fidèle au vrai schéma observé sur ajaxOutage.php. */
const SAMPLE: RawEneoItem[] = [
  {
    observations: "Travaux de maintenance et de sécurisation sur le réseau de distribution",
    prog_date: "2026-06-10",
    prog_heure_debut: "06:00",
    prog_heure_fin: "18:00",
    region: "LITTORAL",
    ville: "DOUALA",
    quartier: "CITE SIC",
  },
  {
    // espace parasite en tête (cas réel)
    observations: "Travaux",
    prog_date: "2026-06-10",
    prog_heure_debut: "06:00",
    prog_heure_fin: "18:00",
    region: "LITTORAL",
    ville: "DOUALA",
    quartier: " QUARTIER GENTIL",
  },
  {
    // quartier vide → doit être ignoré
    observations: "Travaux",
    prog_date: "2026-06-13",
    prog_heure_debut: "06:00",
    prog_heure_fin: "18:00",
    region: "LITTORAL",
    ville: "DOUALA",
    quartier: "",
  },
  {
    // doublon exact de NDOGBONG (1/2)
    observations: "Maintenance",
    prog_date: "2026-06-13",
    prog_heure_debut: "06:00",
    prog_heure_fin: "18:00",
    region: "LITTORAL",
    ville: "DOUALA",
    quartier: "NDOGBONG",
  },
  {
    // doublon : même quartier après trim → même rawHash → dédupliqué
    observations: "Maintenance",
    prog_date: "2026-06-13",
    prog_heure_debut: "06:00",
    prog_heure_fin: "18:00",
    region: "LITTORAL",
    ville: "DOUALA",
    quartier: " NDOGBONG",
  },
];

test("normalizeEneo : trim des espaces parasites du quartier", () => {
  const out = normalizeEneo([SAMPLE[1]]);
  assert.equal(out.length, 1);
  assert.equal(out[0].quartier, "QUARTIER GENTIL");
});

test("normalizeEneo : quartier vide ignoré", () => {
  const out = normalizeEneo([SAMPLE[2]]);
  assert.equal(out.length, 0);
});

test("normalizeEneo : dédup des doublons (même clé après trim)", () => {
  const out = normalizeEneo([SAMPLE[3], SAMPLE[4]]);
  assert.equal(out.length, 1);
  assert.equal(out[0].quartier, "NDOGBONG");
});

test("normalizeEneo : conversion horaire Africa/Douala (UTC+1) → UTC", () => {
  const out = normalizeEneo([SAMPLE[0]]);
  assert.equal(out[0].startsAt.toISOString(), "2026-06-10T05:00:00.000Z");
  assert.equal(out[0].endsAt.toISOString(), "2026-06-10T17:00:00.000Z");
});

test("normalizeEneo : heures locales HH:MM conservées pour l'affichage", () => {
  const [o] = normalizeEneo([SAMPLE[0]]);
  assert.equal(o.startTime, "06:00");
  assert.equal(o.endTime, "18:00");
});

test("normalizeEneo : champs canoniques préservés", () => {
  const [o] = normalizeEneo([SAMPLE[0]]);
  assert.equal(o.provider, "eneo");
  assert.equal(o.country, "CM");
  assert.equal(o.region, "LITTORAL");
  assert.equal(o.ville, "DOUALA");
  assert.equal(o.quartier, "CITE SIC");
  assert.match(o.reason, /maintenance/i);
  assert.equal(o.progDate, "2026-06-10");
});

test("normalizeEneo : rawHash déterministe et stable", () => {
  const a = normalizeEneo([SAMPLE[0]])[0].rawHash;
  const b = normalizeEneo([SAMPLE[0]])[0].rawHash;
  assert.equal(a, b);
  assert.match(a, /^[0-9a-f]{40}$/); // SHA-1 hex
});

test("normalizeEneo : lot complet → 3 entrées uniques (vide exclu, doublon fusionné)", () => {
  const out = normalizeEneo(SAMPLE);
  // CITE SIC, QUARTIER GENTIL, NDOGBONG (×1) → 3 ; vide exclu.
  assert.equal(out.length, 3);
  const quartiers = out.map((o) => o.quartier).sort();
  assert.deepEqual(quartiers, ["CITE SIC", "NDOGBONG", "QUARTIER GENTIL"]);
});
