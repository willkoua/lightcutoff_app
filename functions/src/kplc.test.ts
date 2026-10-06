import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { CanonicalOutage } from "./sources/types";
import {
  extractPdf,
  normalizeKplc,
  parseKplcBlocks,
  parseKplcDate,
  parseTimeToken,
  parseTimeRange,
  discoverPdfUrls,
  reconstructText,
  KplcPage,
  RawKplcPdf,
} from "./sources/kplc";

const FIXTURES = join(__dirname, "..", "test", "fixtures");
const PDF_FILES = [
  "01M3XNAF1QHQ9J5YY5WXW8NCZX.pdf", // "p1" — contient NAIROBI/MARURUI
  "01M3C1MX9XJ89G6Z4EDV615XQ2.pdf", // "p2"
  "01M2TF23PF1769ERZHHT2E2SQT.pdf", // "p3"
];

function loadFixture(name: string): Uint8Array {
  return new Uint8Array(readFileSync(join(FIXTURES, name)));
}

/** Construit une page mono-colonne synthétique (1 item par ligne) pour tests purs. */
function pageFromLines(lines: string[]): KplcPage {
  const items = lines.map((str, i) => ({
    str,
    x0: 40,
    x1: 40 + Math.max(10, str.length * 4),
    y: 800 - i * 12,
  }));
  return { width: 600, items };
}

async function normalizeFixture(name: string): Promise<CanonicalOutage[]> {
  const raw = await extractPdf(loadFixture(name), `https://kplc.co.ke/storage/${name}`);
  return normalizeKplc([raw]);
}

// --- Parse complet sur fixtures réelles --------------------------------------

test("normalizeKplc : chaque PDF d'échantillon donne >= 30 coupures complètes", async () => {
  for (const name of PDF_FILES) {
    const out = await normalizeFixture(name);
    assert.ok(
      out.length >= 30,
      `${name}: ${out.length} coupures (< 30)`
    );
    // date + horaires présents et bien formés sur tout le lot
    for (const o of out) {
      assert.match(o.progDate, /^\d{4}-\d{2}-\d{2}$/, `${name}: progDate ${o.progDate}`);
      assert.match(o.startTime, /^\d{2}:\d{2}$/);
      assert.match(o.endTime, /^\d{2}:\d{2}$/);
      assert.ok(o.quartier.length > 0, `${name}: quartier vide`);
    }
  }
});

test("normalizeKplc : au moins 2 régions distinctes présentes", async () => {
  const out = await normalizeFixture(PDF_FILES[0]);
  const regions = new Set(out.map((o) => o.region));
  assert.ok(regions.size >= 2, `régions: ${[...regions].join(", ")}`);
  assert.ok([...regions].some((r) => /REGION$/.test(r)));
});

test("normalizeKplc : enregistrement connu (NAIROBI / MARURUI) parsé correctement", async () => {
  const out = await normalizeFixture(PDF_FILES[0]);
  const rec = out.find((o) => o.quartier === "MARURUI");
  assert.ok(rec, "MARURUI introuvable");
  assert.equal(rec!.provider, "kplc");
  assert.equal(rec!.country, "KE");
  assert.equal(rec!.region, "NAIROBI REGION");
  assert.equal(rec!.ville, "NAIROBI"); // pas de sous-en-tête comté → repli région
  assert.equal(rec!.progDate, "2026-10-06");
  assert.equal(rec!.startTime, "09:00");
  assert.equal(rec!.endTime, "17:00");
  assert.match(rec!.reason, /Windsor/i);
  assert.match(rec!.rawHash, /^[0-9a-f]{40}$/);
});

test("normalizeKplc : startsAt/endsAt reflètent l'EAT (+03:00)", async () => {
  const out = await normalizeFixture(PDF_FILES[0]);
  const rec = out.find((o) => o.quartier === "MARURUI")!;
  // 09:00 EAT (+03:00) → 06:00 UTC ; 17:00 EAT → 14:00 UTC
  assert.equal(rec.startsAt.toISOString(), "2026-10-06T06:00:00.000Z");
  assert.equal(rec.endsAt.toISOString(), "2026-10-06T14:00:00.000Z");
});

// --- Helpers purs : conversions ----------------------------------------------

test("parseTimeToken : A.M./P.M., points, deux-points, midi/minuit", () => {
  assert.equal(parseTimeToken("9.00 A.M."), "09:00");
  assert.equal(parseTimeToken("5.00 P.M."), "17:00");
  assert.equal(parseTimeToken("9.00 A.M"), "09:00"); // sans point final
  assert.equal(parseTimeToken("5.00 P.M ."), "17:00"); // espace avant point
  assert.equal(parseTimeToken("9.00A.M."), "09:00"); // sans espace
  assert.equal(parseTimeToken("12:00 P.M."), "12:00"); // midi
  assert.equal(parseTimeToken("12:00 A.M."), "00:00"); // minuit
  assert.equal(parseTimeToken("2:30 P.M."), "14:30");
  assert.equal(parseTimeToken("nope"), null);
});

test("parseTimeRange : extrait début et fin quel que soit le séparateur", () => {
  assert.deepEqual(parseTimeRange("9.00 A.M. – 5.00 P.M."), { start: "09:00", end: "17:00" });
  assert.deepEqual(parseTimeRange("8:00 A.M. - 5:00 P.M."), { start: "08:00", end: "17:00" });
  assert.equal(parseTimeRange("9.00 A.M. only"), null);
});

test("parseKplcDate : DD.MM.YYYY → YYYY-MM-DD, tolère ponctuation/espaces", () => {
  assert.equal(parseKplcDate("Monday 05.10.2026"), "2026-10-05");
  assert.equal(parseKplcDate("Wednesday 07.10. 2026"), "2026-10-07"); // espace
  assert.equal(parseKplcDate("Wednesday 07.10.2026,"), "2026-10-07"); // virgule
  assert.equal(parseKplcDate("Wednesday 30.09.2026"), "2026-09-30");
  assert.equal(parseKplcDate("pas de date"), null);
});

// --- Blocs : dédup & blocs incomplets ----------------------------------------

const COMPLETE_LINES = [
  "NAIROBI REGION",
  "AREA: MARURUI",
  "DATE: Tuesday 06.10.2026 TIME: 9.00 A.M. – 5.00 P.M.",
  "Windsor Hotel, Mugumoini & adjacent customers.",
];

test("parseKplcBlocks : bloc incomplet (sans DATE) → progDate null", () => {
  const blocks = parseKplcBlocks(
    [
      "NAIROBI REGION",
      "AREA: KOSOVO",
      "Shofco, Utalii & adjacent customers.", // pas de ligne DATE
      "AREA: MARURUI",
      "DATE: Tuesday 06.10.2026 TIME: 9.00 A.M. – 5.00 P.M.",
      "Windsor Hotel & adjacent customers.",
    ].join("\n")
  );
  const kosovo = blocks.find((b) => b.area === "KOSOVO")!;
  assert.equal(kosovo.progDate, null);
  const marurui = blocks.find((b) => b.area === "MARURUI")!;
  assert.equal(marurui.progDate, "2026-10-06");
  assert.equal(marurui.startTime, "09:00");
});

test("normalizeKplc : ignore les blocs incomplets", () => {
  const pdf: RawKplcPdf = {
    sourceUrl: "x",
    pages: [
      pageFromLines([
        "NAIROBI REGION",
        "AREA: KOSOVO", // incomplet : aucune date
        "Shofco & adjacent customers.",
        ...COMPLETE_LINES,
      ]),
    ],
  };
  const out = normalizeKplc([pdf]);
  assert.equal(out.length, 1);
  assert.equal(out[0].quartier, "MARURUI");
});

test("normalizeKplc : strip du préfixe 'PART OF' sur le quartier", () => {
  const pdf: RawKplcPdf = {
    sourceUrl: "x",
    pages: [
      pageFromLines([
        "NAIROBI REGION",
        "AREA: PART OF RUNDA",
        "DATE: Wednesday 07.10.2026 TIME: 9.00 A.M. – 5.00 P.M.",
        "Runda Drive & adjacent customers.",
      ]),
    ],
  };
  const out = normalizeKplc([pdf]);
  assert.equal(out.length, 1);
  assert.equal(out[0].quartier, "RUNDA");
});

test("normalizeKplc : ville dérivée du sous-en-tête comté", () => {
  const pdf: RawKplcPdf = {
    sourceUrl: "x",
    pages: [
      pageFromLines([
        "NORTH RIFT REGION",
        "PARTS OF UASIN GISHU COUNTY",
        "AREA: ELDORET GK PRISONS",
        "DATE: Sunday 04.10.2026 TIME 9:00 A.M. – 5:00 P.M.",
        "Sirikwa Hotel & adjacent customers.",
      ]),
    ],
  };
  const out = normalizeKplc([pdf]);
  assert.equal(out.length, 1);
  assert.equal(out[0].ville, "UASIN GISHU");
  assert.equal(out[0].region, "NORTH RIFT REGION");
  assert.equal(out[0].startTime, "09:00"); // "TIME" sans ':' géré
});

test("normalizeKplc : dédup par rawHash (même PDF deux fois)", async () => {
  const raw = await extractPdf(loadFixture(PDF_FILES[2]), "u");
  const once = normalizeKplc([raw]);
  const twice = normalizeKplc([raw, raw]);
  assert.equal(twice.length, once.length);
});

// --- Découverte des PDF (helper pur) -----------------------------------------

test("discoverPdfUrls : garde les ULID, trie du plus récent au plus ancien", () => {
  const html = `
    <a href="https://kplc.co.ke/storage/2021(Revised)_Prepaid.pdf">x</a>
    <a href="https://kplc.co.ke/storage/01M2TF23PF1769ERZHHT2E2SQT.pdf">a</a>
    <a href="https://www.kplc.co.ke/storage/01M3XNAF1QHQ9J5YY5WXW8NCZX.pdf">b</a>
    <a href="https://kplc.co.ke/storage/01M3C1MX9XJ89G6Z4EDV615XQ2.pdf">c</a>
    <a href="https://kplc.co.ke/storage/01M3C1MX9XJ89G6Z4EDV615XQ2.pdf">dup</a>
  `;
  const urls = discoverPdfUrls(html, 2);
  assert.equal(urls.length, 2);
  // ULID: 01M3XN… > 01M3C1… > 01M2TF… → les 2 plus récents
  assert.ok(urls[0].includes("01M3XNAF1QHQ9J5YY5WXW8NCZX"));
  assert.ok(urls[1].includes("01M3C1MX9XJ89G6Z4EDV615XQ2"));
  assert.ok(!urls.some((u) => u.includes("Prepaid")));
});

test("reconstructText : ordre colonne-par-colonne respecté", () => {
  // deux colonnes séparées par une large gouttière vide
  const items = [
    { str: "LEFT-TOP", x0: 20, x1: 100, y: 500 },
    { str: "LEFT-BOT", x0: 20, x1: 100, y: 480 },
    { str: "RIGHT-TOP", x0: 300, x1: 380, y: 500 },
    { str: "RIGHT-BOT", x0: 300, x1: 380, y: 480 },
  ];
  const text = reconstructText([{ width: 420, items }]);
  assert.equal(text, "LEFT-TOP\nLEFT-BOT\nRIGHT-TOP\nRIGHT-BOT");
});
