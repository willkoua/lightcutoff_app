/**
 * Adaptateur Kenya Power (KPLC, Kenya) — « Planned Power Interruptions ».
 *
 * Source : https://kplc.co.ke/customer-support publie des PDF « Planned Power
 * Interruptions » (noms de fichier ULID, triables par date) sous
 * `/storage/<ULID>.pdf`. Chaque PDF est une notice multi-colonnes :
 *
 *   NAIROBI REGION                 ← en-tête RÉGION (CAPS, finit par "REGION")
 *   PARTS OF NAIROBI COUNTY        ← sous-en-tête comté optionnel
 *   AREA: MARURUI                  ← zone (quartier user-facing)
 *   DATE: Tuesday 06.10.2026 TIME: 9.00 A.M. – 5.00 P.M.
 *   Windsor Hotel, ... & adjacent customers.   ← liste rues/repères (reason)
 *
 * Mise en page vérifiée (2026-10-06) : 2 colonnes, ordre de lecture
 * colonne-par-colonne (colonne gauche entière de haut en bas, puis la suivante).
 * On détecte les colonnes par histogramme d'occupation en X (gouttières
 * verticales vides), on regroupe les items par Y en lignes, puis on parse les
 * blocs structurés. Les 3 PDF d'échantillon donnent 40–58 blocs AREA, parsés
 * à 100 % (date + horaires complets).
 *
 * Fragilités de format tolérées (observées en live) :
 *   - séparateur horaire `–`, `—` ou `-` ;
 *   - horaires `9.00 A.M.`, `9.00 A.M` (sans point final), `9.00 A.M .`
 *     (espace avant le point), `9.00A.M.` (sans espace), `12:00 P.M.` (avec `:`) ;
 *   - `DATE :` / `TIME` avec/ sans `:` et espaces variables ;
 *   - date `07.10.2026`, `07.10. 2026` (espace), `07.10.2026.` / `,` (ponctuation).
 *
 * Heures locales **Africa/Nairobi = EAT = UTC+3 (pas de DST)**.
 *
 * I/O (réseau + extraction pdfjs) dans `fetch()` ; `normalizeKplc` est **pure**
 * (aucune I/O) → testée sur des Buffers de fixtures dans `kplc.test.ts`.
 */
import { createHash } from "node:crypto";
import { CanonicalOutage, OutageSourceAdapter } from "./types";

/** Page listant les PDF de coupures planifiées. */
export const KPLC_LISTING_URL = "https://kplc.co.ke/customer-support";
/** Décalage horaire local KPLC (Africa/Nairobi = EAT = UTC+3, pas de DST). */
const KPLC_TZ_OFFSET = "+03:00";
/** Nombre de PDF (les plus récents) téléchargés par défaut (fenêtre multi-jours). */
const KPLC_DEFAULT_MAX_PDFS = 3;

/** Un item texte extrait par pdfjs : chaîne + bornes X et position Y (repère PDF, Y vers le haut). */
export interface KplcTextItem {
  str: string;
  x0: number;
  x1: number;
  y: number;
}

/** Une page extraite : largeur + items texte. */
export interface KplcPage {
  width: number;
  items: KplcTextItem[];
}

/** Données brutes d'un PDF (ce que `fetch` renvoie et que `normalize` consomme). */
export interface RawKplcPdf {
  sourceUrl: string;
  pages: KplcPage[];
}

/** Bloc structuré intermédiaire (avant mapping canonique). */
export interface KplcBlock {
  region: string | null;
  county: string | null;
  area: string;
  progDate: string | null;
  startTime: string | null;
  endTime: string | null;
  reason: string;
}

// --- Patterns de parsing (tolérants aux variantes observées en live) ---------
const RE_REGION = /^([A-Z][A-Z .&/-]*REGION)\s*$/;
const RE_COUNTY = /^(PARTS? OF [A-Z .'’]+COUNTY)\s*$/i;
const RE_AREA = /^AREA\s*:\s*(.+)/i;
const RE_DATELINE = /\bDATE\s*:?\s*(.+?)\s*\bTIME\b\s*:?\s*(.+)/i;
const RE_DATETOK = /(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})/;
const RE_TIMETOK = /(\d{1,2})[.:](\d{2})\s*([AP])\.?\s*M/gi;
const RE_INLINE_DATE = /\bDATE\s*:/i;
/** PDF nommés par ULID (26 car. Crockford base32) sous /storage/. */
const RE_ULID_PDF =
  /https?:\/\/[^\s"'<>]*\/storage\/([0-9A-HJKMNP-TV-Z]{26})\.pdf/gi;

function hashId(...parts: string[]): string {
  return createHash("sha1").update(parts.join("|")).digest("hex");
}

/**
 * Détecte les frontières de colonnes par histogramme d'occupation en X :
 * une gouttière = un intervalle d'au moins 18 px sans aucun texte, à l'écart
 * des marges. Renvoie les bornes `[0, ...gaps, width]`. **Pure.**
 */
export function detectColumns(items: KplcTextItem[], pageWidth: number): number[] {
  const bins = Math.ceil(pageWidth) + 1;
  const occ = new Array<number>(bins).fill(0);
  for (const it of items) {
    const a = Math.max(0, Math.floor(it.x0));
    const b = Math.min(bins - 1, Math.floor(it.x1));
    for (let x = a; x <= b; x++) occ[x]++;
  }
  const gaps: number[] = [];
  let run = 0;
  let start = 0;
  for (let x = 0; x < bins; x++) {
    if (occ[x] === 0) {
      if (run === 0) start = x;
      run++;
    } else {
      if (run >= 18 && start > 5 && x < pageWidth - 5) {
        gaps.push(Math.floor((start + x) / 2));
      }
      run = 0;
    }
  }
  return [0, ...gaps, Math.ceil(pageWidth)];
}

/**
 * Reconstruit le texte en respectant l'ordre de lecture colonne-par-colonne :
 * pour chaque colonne, items triés par Y décroissant (haut de page d'abord)
 * puis regroupés en lignes (même Y à ±4 px), colonnes concaténées de gauche à
 * droite. **Pure.**
 */
export function reconstructText(pages: KplcPage[]): string {
  const out: string[] = [];
  for (const pg of pages) {
    const bounds = detectColumns(pg.items, pg.width);
    for (let ci = 0; ci < bounds.length - 1; ci++) {
      const lo = bounds[ci];
      const hi = bounds[ci + 1];
      const col = pg.items.filter((w) => {
        const c = (w.x0 + w.x1) / 2;
        return c >= lo && c < hi;
      });
      col.sort((a, b) => b.y - a.y || a.x0 - b.x0);
      const lines: KplcTextItem[][] = [];
      let cur: KplcTextItem[] = [];
      let cy: number | null = null;
      for (const w of col) {
        if (cy === null || Math.abs(w.y - cy) <= 4) cur.push(w);
        else {
          lines.push(cur);
          cur = [w];
        }
        cy = w.y;
      }
      if (cur.length) lines.push(cur);
      for (const ln of lines) {
        ln.sort((a, b) => a.x0 - b.x0);
        out.push(
          ln
            .map((w) => w.str.trim())
            .filter(Boolean)
            .join(" ")
        );
      }
    }
  }
  return out.join("\n");
}

/**
 * `"Tuesday 06.10.2026"` → `"2026-10-06"`. Tolère espaces/ponctuation parasites.
 * `null` si aucune date `DD.MM.YYYY` trouvée. **Pure.**
 */
export function parseKplcDate(raw: string): string | null {
  const m = raw.match(RE_DATETOK);
  if (!m) return null;
  const [, dd, mm, yyyy] = m;
  return `${yyyy}-${mm.padStart(2, "0")}-${dd.padStart(2, "0")}`;
}

/**
 * Jeton horaire `"9.00 A.M."` / `"12:00 P.M."` / `"9.00A.M"` → `"HH:MM"` (24 h).
 * Midi `12 P.M.` → `12:00`, minuit `12 A.M.` → `00:00`. `null` si invalide. **Pure.**
 */
export function parseTimeToken(tok: string): string | null {
  const m = tok.match(/(\d{1,2})[.:](\d{2})\s*([AP])\.?\s*M/i);
  if (!m) return null;
  let hour = Number(m[1]);
  const minute = m[2];
  const pm = /p/i.test(m[3]);
  if (hour < 1 || hour > 12 || Number(minute) > 59) return null;
  if (pm) {
    if (hour !== 12) hour += 12;
  } else if (hour === 12) {
    hour = 0;
  }
  return `${String(hour).padStart(2, "0")}:${minute}`;
}

/**
 * Extrait les deux premiers jetons horaires d'un segment TIME (`… 9.00 A.M. – 5.00 P.M.`).
 * `null` si moins de deux horaires valides. **Pure.**
 */
export function parseTimeRange(raw: string): { start: string; end: string } | null {
  const toks = raw.match(RE_TIMETOK);
  if (!toks || toks.length < 2) return null;
  const start = parseTimeToken(toks[0]);
  const end = parseTimeToken(toks[1]);
  if (!start || !end) return null;
  return { start, end };
}

/**
 * Parse le texte reconstruit en blocs structurés (région / comté / zone /
 * date / horaires / liste de lieux). Un bloc commence à chaque `AREA:` ; la
 * ligne `DATE: … TIME: …` suivante (ou en fin de ligne AREA) le complète ;
 * les lignes restantes jusqu'au prochain en-tête forment la liste de lieux.
 * **Pure.**
 */
export function parseKplcBlocks(text: string): KplcBlock[] {
  const blocks: KplcBlock[] = [];
  let region: string | null = null;
  let county: string | null = null;
  let cur: KplcBlock | null = null;
  let buf: string[] = [];

  const flush = () => {
    if (cur) {
      cur.reason = buf.join(" ").replace(/\s+/g, " ").trim();
      blocks.push(cur);
    }
    cur = null;
    buf = [];
  };

  for (const rawLine of text.split("\n")) {
    const s = rawLine.trim();
    if (!s) continue;

    if (RE_REGION.test(s)) {
      flush();
      region = s.replace(/\s+/g, " ");
      county = null;
      continue;
    }
    if (RE_COUNTY.test(s)) {
      flush();
      county = s.replace(/\s+/g, " ");
      continue;
    }

    let rest = s;
    const am = s.match(RE_AREA);
    if (am) {
      flush();
      // La ligne AREA peut déborder sur un DATE: inline (rare) → on scinde.
      const idx = am[1].search(RE_INLINE_DATE);
      const area = idx >= 0 ? am[1].slice(0, idx) : am[1];
      cur = {
        region,
        county,
        area: area.trim(),
        progDate: null,
        startTime: null,
        endTime: null,
        reason: "",
      };
      rest = idx >= 0 ? am[1].slice(idx) : "";
    }

    if (cur && !cur.progDate) {
      const d = rest.match(RE_DATELINE);
      if (d) {
        cur.progDate = parseKplcDate(d[1]);
        const tr = parseTimeRange(d[2]);
        if (tr) {
          cur.startTime = tr.start;
          cur.endTime = tr.end;
        }
        continue;
      }
    }

    if (am) continue; // ligne AREA sans DATE inline : on attend la ligne DATE
    // Les parenthèses = blurb d'en-tête ("(It is necessary…)"), jamais un lieu.
    if (cur && !s.startsWith("(")) buf.push(s);
  }
  flush();
  return blocks;
}

/** Comté → ville : `"PARTS OF UASIN GISHU COUNTY"` → `"UASIN GISHU"`. */
function countyToVille(county: string): string {
  return county
    .replace(/^PARTS?\s+OF\s+/i, "")
    .replace(/\s+COUNTY$/i, "")
    .trim();
}

/** Région → ville de repli : `"NAIROBI REGION"` → `"NAIROBI"` (simple, documenté). */
function regionToVille(region: string): string {
  return region.replace(/\s+REGION$/i, "").trim();
}

/** Zone → quartier : retire un préfixe `"PART OF "` / `"PARTS OF "` éventuel. */
function areaToQuartier(area: string): string {
  return area.replace(/^PARTS?\s+OF\s+/i, "").trim();
}

/**
 * Transforme les PDF bruts (déjà extraits par pdfjs) en schéma canonique.
 * **Fonction pure** (aucune I/O) :
 *   - reconstruit le texte colonne-par-colonne puis parse les blocs ;
 *   - ignore les blocs inexploitables (zone/date/horaire manquants ou invalides) ;
 *   - déduplique le lot par `rawHash` (upsert idempotent).
 */
export function normalizeKplc(raw: RawKplcPdf[]): CanonicalOutage[] {
  const byHash = new Map<string, CanonicalOutage>();
  for (const pdf of raw) {
    const text = reconstructText(pdf.pages);
    for (const b of parseKplcBlocks(text)) {
      const quartier = areaToQuartier(b.area);
      if (!quartier || !b.progDate || !b.startTime || !b.endTime) continue;

      const region = (b.region ?? "").trim();
      const ville = b.county ? countyToVille(b.county) : regionToVille(region);

      const startsAt = new Date(`${b.progDate}T${b.startTime}:00${KPLC_TZ_OFFSET}`);
      const endsAt = new Date(`${b.progDate}T${b.endTime}:00${KPLC_TZ_OFFSET}`);
      if (isNaN(startsAt.getTime()) || isNaN(endsAt.getTime())) continue;

      const rawHash = hashId(
        "kplc",
        region,
        ville,
        quartier,
        b.progDate,
        b.startTime,
        b.endTime
      );
      if (byHash.has(rawHash)) continue; // dédup intra-lot

      byHash.set(rawHash, {
        provider: "kplc",
        country: "KE",
        region,
        ville,
        quartier,
        reason: b.reason,
        progDate: b.progDate,
        startTime: b.startTime,
        endTime: b.endTime,
        startsAt,
        endsAt,
        rawHash,
        sourceUrl: pdf.sourceUrl,
      });
    }
  }
  return [...byHash.values()];
}

/**
 * Extrait les URLs de PDF de coupures (noms ULID) d'une page HTML, dédupliquées
 * et triées **du plus récent au plus ancien** (l'ULID est lexicographiquement
 * monotone dans le temps). **Pure.**
 */
export function discoverPdfUrls(
  html: string,
  max = KPLC_DEFAULT_MAX_PDFS
): string[] {
  const byUlid = new Map<string, string>();
  for (const m of html.matchAll(RE_ULID_PDF)) {
    const url = m[0];
    const ulid = m[1].toUpperCase();
    if (!byUlid.has(ulid)) byUlid.set(ulid, url);
  }
  return [...byUlid.keys()]
    .sort((a, b) => (a < b ? 1 : a > b ? -1 : 0))
    .slice(0, max)
    .map((u) => byUlid.get(u)!);
}

/** Importe pdfjs (ESM) depuis une sortie CommonJS sans que tsc ne réécrive l'import. */
const dynamicImport = new Function("spec", "return import(spec)") as (
  spec: string
) => Promise<any>;

/**
 * Extrait les items texte d'un PDF (positions X/Y) via pdfjs-dist (legacy build,
 * Node). Déterministe et sans réseau → on peut faire tourner tout le parse sur
 * un Buffer de fixture dans les tests.
 */
export async function extractPdf(
  data: Uint8Array | Buffer,
  sourceUrl: string
): Promise<RawKplcPdf> {
  const pdfjs = await dynamicImport("pdfjs-dist/legacy/build/pdf.mjs");
  // pdfjs exige un Uint8Array « nu » : un Node Buffer passe `instanceof
  // Uint8Array` (il en hérite) mais est rejeté par pdfjs → recopier dans un
  // Uint8Array simple. `fetch()` fournit déjà un Uint8Array, mais un appelant
  // (test, script) peut passer un Buffer.
  const isPlainU8 =
    data instanceof Uint8Array &&
    !(typeof Buffer !== "undefined" && Buffer.isBuffer(data));
  const bytes = isPlainU8 ? data : new Uint8Array(data);
  const task = pdfjs.getDocument({
    data: bytes,
    isEvalSupported: false,
    useSystemFonts: false,
    verbosity: 0,
  });
  const doc = await task.promise;
  const pages: KplcPage[] = [];
  try {
    for (let p = 1; p <= doc.numPages; p++) {
      const page = await doc.getPage(p);
      const width = page.getViewport({ scale: 1 }).width;
      const tc = await page.getTextContent();
      const items: KplcTextItem[] = [];
      for (const it of tc.items as any[]) {
        const str: string = it.str ?? "";
        if (!str) continue;
        const x0: number = it.transform[4];
        const y: number = it.transform[5];
        const w: number = it.width ?? 0;
        items.push({ str, x0, x1: x0 + w, y });
      }
      pages.push({ width, items });
    }
  } finally {
    await task.destroy();
  }
  return { sourceUrl, pages };
}

export class KplcAdapter implements OutageSourceAdapter {
  readonly provider = "kplc";
  readonly country = "KE";

  constructor(private readonly maxPdfs = KPLC_DEFAULT_MAX_PDFS) {}

  /** Découvre les URLs des PDF les plus récents (I/O réseau). */
  async discover(): Promise<string[]> {
    const res = await fetch(KPLC_LISTING_URL, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; NjukaBot/1.0)" },
    });
    if (!res.ok) throw new Error(`KPLC listing: HTTP ${res.status}`);
    return discoverPdfUrls(await res.text(), this.maxPdfs);
  }

  /**
   * Télécharge et extrait les PDF les plus récents. **Résilient par PDF** : un
   * échec (réseau ou extraction) est journalisé et ignoré — la donnée officielle
   * est un bonus, jamais une dépendance bloquante.
   */
  async fetch(): Promise<RawKplcPdf[]> {
    let urls: string[] = [];
    try {
      urls = await this.discover();
    } catch (e) {
      console.warn("KplcAdapter: échec découverte des PDF (ignorée)", e);
      return [];
    }
    const out: RawKplcPdf[] = [];
    for (const url of urls) {
      try {
        const res = await fetch(url, {
          headers: { "User-Agent": "Mozilla/5.0 (compatible; NjukaBot/1.0)" },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const buf = new Uint8Array(await res.arrayBuffer());
        out.push(await extractPdf(buf, url));
      } catch (e) {
        console.warn(`KplcAdapter: échec PDF ${url} (ignoré)`, e);
      }
    }
    return out;
  }

  normalize(raw: RawKplcPdf[]): CanonicalOutage[] {
    return normalizeKplc(raw);
  }
}
