import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { CanonicalOutage } from "./sources/types";
import { extractPdf, RawKplcPdf } from "./sources/kplc";
import {
  normalizeNairobiWater,
  parseNwDate,
  parseNwTime,
  parseNwWindow,
  splitNwBullets,
  discoverNwPdfUrls,
  isTwoColumn,
} from "./sources/nairobiwater";

const FIXTURES = join(__dirname, "..", "test", "fixtures");
const FEB_2026 = "nwater_feb2026.pdf"; // format riche 2 colonnes (cible)
const OCT_2024 = "nwater.pdf"; // ancien format prose mono-colonne

function loadFixture(name: string): Uint8Array {
  return new Uint8Array(readFileSync(join(FIXTURES, name)));
}

async function rawFixture(name: string): Promise<RawKplcPdf> {
  return extractPdf(loadFixture(name), `https://nairobiwater.co.ke/wp-content/${name}`);
}

async function normalizeFixture(name: string): Promise<CanonicalOutage[]> {
  return normalizeNairobiWater([await rawFixture(name)]);
}

// --- Parse complet sur la notice riche Fév. 2026 (cible) ---------------------

test("normalizeNairobiWater : la notice Fév. 2026 donne >= 8 zones", async () => {
  const out = await normalizeFixture(FEB_2026);
  assert.ok(out.length >= 8, `${out.length} coupures (< 8)`);
  for (const o of out) {
    assert.equal(o.service, "water");
    assert.equal(o.provider, "nairobi_water");
    assert.equal(o.country, "KE");
    assert.equal(o.region, "NAIROBI");
    assert.equal(o.ville, "NAIROBI");
    assert.ok(o.quartier.length > 0, "quartier vide");
    assert.match(o.progDate, /^\d{4}-\d{2}-\d{2}$/, `progDate ${o.progDate}`);
    assert.match(o.startTime, /^\d{2}:\d{2}$/);
    assert.match(o.endTime, /^\d{2}:\d{2}$/);
    assert.match(o.rawHash, /^[0-9a-f]{40}$/);
    assert.equal(o.sourceUrl.endsWith(FEB_2026), true);
  }
});

test("normalizeNairobiWater : une zone connue parsée correctement (date/heure)", async () => {
  const out = await normalizeFixture(FEB_2026);
  const rec = out.find((o) =>
    /Kileleshwa|Kilimani|Karen/.test(o.quartier)
  );
  assert.ok(rec, "aucune zone Kileleshwa/Kilimani/Karen trouvée");
  assert.equal(rec!.progDate, "2026-02-20");
  assert.equal(rec!.startTime, "06:00");
  assert.equal(rec!.endTime, "08:00");
  assert.ok(rec!.reason.length > 0, "liste de rues (reason) vide");
});

test("normalizeNairobiWater : fenêtre multi-jours + EAT (+03:00)", async () => {
  const out = await normalizeFixture(FEB_2026);
  const rec = out.find((o) => /Kileleshwa|Kilimani|Karen/.test(o.quartier))!;
  // Début 06:00 EAT (+03:00) le 20 fév. → 03:00 UTC le 20 fév.
  assert.equal(rec.startsAt.toISOString(), "2026-02-20T03:00:00.000Z");
  // Fin le LENDEMAIN (21 fév.) à 08:00 EAT → 05:00 UTC le 21 fév.
  assert.equal(rec.endsAt.toISOString(), "2026-02-21T05:00:00.000Z");
  assert.equal(rec.endsAt.getUTCDate(), 21);
});

test("normalizeNairobiWater : au moins une zone attendue présente", async () => {
  const out = await normalizeFixture(FEB_2026);
  const quartiers = out.map((o) => o.quartier).join(" | ");
  for (const expected of ["Kileleshwa", "Kilimani", "Karen", "Kibera"]) {
    assert.ok(
      out.some((o) => o.quartier.includes(expected)),
      `zone « ${expected} » absente — trouvées: ${quartiers}`
    );
  }
});

test("normalizeNairobiWater : dédup par rawHash (même PDF deux fois)", async () => {
  const raw = await rawFixture(FEB_2026);
  const once = normalizeNairobiWater([raw]);
  const twice = normalizeNairobiWater([raw, raw]);
  assert.equal(twice.length, once.length);
  // rawHash tous distincts dans un lot
  assert.equal(new Set(once.map((o) => o.rawHash)).size, once.length);
});

// --- Ancien format prose (Oct. 2024) : best-effort, ne doit pas crasher ------

test("normalizeNairobiWater : ancien format prose parsé sans crash", async () => {
  const out = await normalizeFixture(OCT_2024);
  assert.ok(out.length >= 3, `${out.length} coupures (< 3)`);
  for (const o of out) {
    assert.equal(o.service, "water");
    assert.equal(o.provider, "nairobi_water");
    assert.equal(o.progDate, "2024-10-03");
    assert.equal(o.startTime, "06:00");
    assert.ok(o.quartier.length > 0);
  }
  // Fenêtre multi-jours : fin le 04 oct.
  assert.equal(out[0].endsAt.toISOString(), "2024-10-04T03:00:00.000Z");
});

// --- Helpers purs : dates --------------------------------------------------

test("parseNwDate : ordinaux, espaces, noms de mois complets", () => {
  assert.equal(parseNwDate("20th February 2026"), "2026-02-20");
  assert.equal(parseNwDate("20 th February 2026"), "2026-02-20"); // espace avant l'ordinal
  assert.equal(parseNwDate("21st February 2026"), "2026-02-21");
  assert.equal(parseNwDate("Thursday 03 October 2024"), "2024-10-03"); // sans ordinal
  assert.equal(parseNwDate("1st January 2027"), "2027-01-01");
  assert.equal(parseNwDate("3rd Oct 2024"), "2024-10-03"); // abréviation
  assert.equal(parseNwDate("no date here"), null);
});

// --- Helpers purs : horaires -----------------------------------------------

test("parseNwTime : 24h, am/pm avec ou sans espace, midi/minuit", () => {
  assert.equal(parseNwTime("06:00 am"), "06:00");
  assert.equal(parseNwTime("6:00am"), "06:00"); // sans espace, sans zéro
  assert.equal(parseNwTime("08:00 am"), "08:00");
  assert.equal(parseNwTime("2:30 pm"), "14:30");
  assert.equal(parseNwTime("12:00 pm"), "12:00"); // midi
  assert.equal(parseNwTime("12:00 am"), "00:00"); // minuit
  assert.equal(parseNwTime("nope"), null);
});

// --- Helpers purs : fenêtre ------------------------------------------------

test("parseNwWindow : phrasé « from <date> at <time> to <date> at <time> »", () => {
  const w = parseNwWindow(
    "from 20th February 2026 at 06:00 am to 21st February 2026 at 08:00 am to carry out"
  );
  assert.deepEqual(w, {
    startDate: "2026-02-20",
    endDate: "2026-02-21",
    startTime: "06:00",
    endTime: "08:00",
  });
});

test("parseNwWindow : phrasé « start at <time> on <date> up to <time> on <date> »", () => {
  const w = parseNwWindow(
    "start at 6:00am on Thursday 03 October 2024 up to 6:00am on Friday 04 October 2024"
  );
  assert.deepEqual(w, {
    startDate: "2024-10-03",
    endDate: "2024-10-04",
    startTime: "06:00",
    endTime: "06:00",
  });
});

test("parseNwWindow : fenêtre mono-jour (une seule date/heure) retombe sur le début", () => {
  const w = parseNwWindow("on 5th March 2026 at 09:00 am");
  assert.deepEqual(w, {
    startDate: "2026-03-05",
    endDate: "2026-03-05",
    startTime: "09:00",
    endTime: "09:00",
  });
});

test("parseNwWindow : null si pas de date/heure exploitables", () => {
  assert.equal(parseNwWindow("the water supply will be interrupted soon"), null);
});

// --- Helpers purs : découpe des puces --------------------------------------

test("splitNwBullets : ignore le préambule, scinde sur « • », aplatit", () => {
  const segs = splitNwBullets(
    "intro à ignorer\n• Alpha — rue A,\nrue B.\n• Beta — rue C."
  );
  assert.equal(segs.length, 2);
  assert.equal(segs[0], "Alpha — rue A, rue B.");
  assert.equal(segs[1], "Beta — rue C.");
});

test("splitNwBullets : texte sans puce → tableau vide", () => {
  assert.deepEqual(splitNwBullets("aucune puce ici"), []);
});

// --- Détection colonnes + mapping sur pages synthétiques --------------------

test("isTwoColumn : vrai si >= 2 puces dans la moitié droite", () => {
  const twoCol = {
    width: 400,
    items: [
      { str: "•", x0: 10, x1: 14, y: 500 },
      { str: "•", x0: 210, x1: 214, y: 500 },
      { str: "•", x0: 210, x1: 214, y: 480 },
    ],
  };
  assert.equal(isTwoColumn([twoCol]), true);
  const oneCol = {
    width: 400,
    items: [
      { str: "•", x0: 10, x1: 14, y: 500 },
      { str: "•", x0: 10, x1: 14, y: 480 },
    ],
  };
  assert.equal(isTwoColumn([oneCol]), false);
});

test("normalizeNairobiWater : puce structurée → quartier nettoyé + reason", () => {
  // Page mono-colonne synthétique : intro (fenêtre) puis deux puces.
  const lines = [
    "WATER SUPPLY INTERRUPTION",
    "shut down from 20th February 2026 at 06:00 am to 21st February 2026 at 08:00 am",
    "interruptions in the following areas:",
    "• Westlands / Lavington areas — Riverside Drive, Chalbi Drive, and surrounding environs.",
    "• Kileleshwa — Kandara Road, Gichugu Road, and environs.",
    "We appeal to all affected customers.",
  ];
  const pdf: RawKplcPdf = {
    sourceUrl: "x",
    pages: [
      {
        width: 600,
        items: lines.map((str, i) => ({
          str,
          x0: 40,
          x1: 40 + Math.max(10, str.length * 4),
          y: 800 - i * 12,
        })),
      },
    ],
  };
  const out = normalizeNairobiWater([pdf]);
  assert.equal(out.length, 2);
  const west = out.find((o) => o.quartier === "Westlands / Lavington")!;
  assert.ok(west, "Westlands / Lavington introuvable");
  assert.equal(west.reason, "Riverside Drive, Chalbi Drive, and surrounding environs.");
  const kile = out.find((o) => o.quartier === "Kileleshwa")!;
  assert.ok(kile, "Kileleshwa introuvable");
  assert.ok(!/We appeal/.test(kile.reason), "reason pollué par le boilerplate");
});

// --- Découverte via l'API WordPress (helper pur) ----------------------------

test("discoverNwPdfUrls : garde les PDF d'interruption, exclut le hors-sujet", () => {
  const items = [
    {
      date: "2026-02-18T10:00:00",
      source_url: "https://nairobiwater.co.ke/wp-content/water-interruption-feb.pdf",
      title: { rendered: "Water Supply Interruption Notice" },
    },
    {
      date: "2024-10-01T10:00:00",
      source_url: "https://nairobiwater.co.ke/wp-content/interruption-oct.pdf",
      title: "Interruption October",
    },
    {
      date: "2026-03-01T10:00:00",
      source_url: "https://nairobiwater.co.ke/wp-content/banking-interruption.pdf",
      title: { rendered: "Banking services interruption" }, // hors-sujet
    },
    {
      date: "2026-02-20T10:00:00",
      source_url: "https://nairobiwater.co.ke/wp-content/tariff.pdf",
      title: { rendered: "New tariff" }, // pas "interruption"
    },
  ];
  const urls = discoverNwPdfUrls(items, 5);
  assert.equal(urls.length, 2);
  // triés du plus récent (fév. 2026) au plus ancien (oct. 2024)
  assert.ok(urls[0].includes("water-interruption-feb"));
  assert.ok(urls[1].includes("interruption-oct"));
  assert.ok(!urls.some((u) => u.includes("banking")));
  assert.ok(!urls.some((u) => u.includes("tariff")));
});

test("discoverNwPdfUrls : respecte la limite max", () => {
  const items = Array.from({ length: 5 }, (_, i) => ({
    date: `2026-02-${10 + i}T10:00:00`,
    source_url: `https://nairobiwater.co.ke/interruption-${i}.pdf`,
    title: "Water Interruption",
  }));
  assert.equal(discoverNwPdfUrls(items, 2).length, 2);
});
