/**
 * Adaptateur Nairobi Water (NCWSC, Kenya) — « Water Supply Interruption ».
 *
 * Source : https://nairobiwater.co.ke publie des PDF « PUBLIC NOTICE — WATER
 * SUPPLY INTERRUPTION ». Les listes HTML du site sont périmées ; l'API REST
 * WordPress renvoie elle les médias de façon fiable :
 *
 *   GET /wp-json/wp/v2/media?search=interruption&per_page=20&orderby=date
 *       &order=desc&_fields=date,source_url,title
 *
 * → tableau JSON de `{ date, source_url, title }`. La `date` est la date
 * d'UPLOAD (pas la date de la coupure) : on ne s'en sert que pour trouver les
 * PDF candidats, on télécharge et on parse pour obtenir les vraies dates.
 *
 * Deux formats de notice observés en live :
 *
 *   • Format « riche » (Fév. 2026, la cible) — mise en page 2 COLONNES, lecture
 *     colonne-par-colonne. Une seule fenêtre horaire dans le paragraphe
 *     d'intro :
 *       "…shut down the Sasumua Water Treatment Plant from 20th February 2026
 *        at 06:00 am to 21st February 2026 at 08:00 am to carry out…"
 *     (la fenêtre peut s'étendre sur PLUSIEURS jours → `endsAt` utilise la date
 *     de FIN). Puis des puces « • <ZONE> — <rues/repères> … and environs. »
 *     séparées par « • ». Le tiret zone↔rues est un cadratin « — » (U+2014) ;
 *     on tolère aussi « – » (demi-cadratin) et « - ».
 *
 *   • Format « prose » plus ancien (Oct. 2024) — mono-colonne, puces sans
 *     structure « <zone> — <rues> » sous « Areas to be affected include: ».
 *     Traité au mieux : une coupure par puce (quartier = label court, reason =
 *     texte de la puce). Résultat plus grossier, assumé.
 *
 * Heures locales **Africa/Nairobi = EAT = UTC+3 (pas de DST)**.
 *
 * I/O (API WordPress + téléchargement + extraction pdfjs) dans `fetch()` ;
 * `normalizeNairobiWater` est **pure** (aucune I/O) → testée sur des Buffers de
 * fixtures dans `nairobiwater.test.ts`. On RÉUTILISE les helpers de `./kplc`
 * (`extractPdf`, `reconstructText`) pour l'extraction et la reconstruction.
 */
import { createHash } from "node:crypto";
import { CanonicalOutage, OutageSourceAdapter } from "./types";
import {
  extractPdf,
  reconstructText,
  KplcPage,
  KplcTextItem,
  RawKplcPdf,
} from "./kplc";

/** API REST WordPress qui liste les médias (PDF de notices). */
export const NAIROBI_WATER_MEDIA_API =
  "https://nairobiwater.co.ke/wp-json/wp/v2/media?search=interruption&per_page=20&orderby=date&order=desc&_fields=date,source_url,title";
/** Décalage horaire local (Africa/Nairobi = EAT = UTC+3, pas de DST). */
const NW_TZ_OFFSET = "+03:00";
/** Nombre de PDF (les plus récents) téléchargés par défaut. */
const NW_DEFAULT_MAX_PDFS = 3;

/** Un média renvoyé par l'API WordPress (champs utiles seulement). */
export interface NwMediaItem {
  date?: string;
  source_url?: string;
  title?: { rendered?: string } | string;
}

/** Fenêtre d'interruption extraite de l'intro (dates locales + horaires 24 h). */
export interface NwWindow {
  startDate: string; // YYYY-MM-DD
  endDate: string; // YYYY-MM-DD (peut différer → fenêtre multi-jours)
  startTime: string; // HH:MM
  endTime: string; // HH:MM
}

/** Puce structurée intermédiaire (avant mapping canonique). */
export interface NwBullet {
  quartier: string;
  reason: string;
}

// --- Patterns de parsing (tolérants aux variantes observées en live) ---------

/** Mois (noms complets + abréviations usuelles) → index 0-based. */
const MONTHS: Record<string, number> = {
  jan: 0, january: 0,
  feb: 1, february: 1,
  mar: 2, march: 2,
  apr: 3, april: 3,
  may: 4,
  jun: 5, june: 5,
  jul: 6, july: 6,
  aug: 7, august: 7,
  sep: 8, sept: 8, september: 8,
  oct: 9, october: 9,
  nov: 10, november: 10,
  dec: 11, december: 11,
};
const MONTH_ALT = Object.keys(MONTHS)
  .sort((a, b) => b.length - a.length) // les plus longs d'abord (greedy)
  .join("|");
/** `20th February 2026`, `20 th February 2026`, `03 October 2024` (ordinal optionnel, espace toléré). */
const RE_DATE = new RegExp(
  `(\\d{1,2})\\s*(?:st|nd|rd|th)?\\s+(${MONTH_ALT})\\.?\\s+(\\d{4})`,
  "gi"
);
/** `06:00 am`, `6:00am`, `08:00 am`, `12.30 pm` → heure/min + am/pm. */
const RE_TIME = /(\d{1,2})[:.](\d{2})\s*([ap])\.?\s*m\b/gi;
/** Séparateur zone↔rues : un tiret ENTOURÉ d'espaces (cadratin, demi-cadratin ou simple). */
const RE_DASH = /\s[—–-]\s/;
/**
 * Boilerplate de bas de notice : la `reason` est tronquée au premier de ces
 * marqueurs (appel aux clients, signature, coordonnées, en-tête de colonne
 * voisine). Les noms de rue légitimes (« Water Front », « Mombasa road »…) ne
 * matchent pas (on exige le contexte complet « Nairobi … Water », etc.).
 */
const RE_BOILERPLATE =
  /\bWe appeal\b|\bAny inconvenience\b|\bToll[-\s]?free\b|\bToll Free\b|\|?\s*Email\s*:|\bManaging Director\b|\bAg\.\s*Managing\b|\bMartin Nang|\bEng\.\s*Nahason|\bPUBLIC NOTICE\b|\bWATER SUPPLY INTERRUPTION\b|\bThis exercise\b|\bNairobi City Water\b|\bNairobi Water (?:Company|Customer)\b|\bNairobiWater\b|\bNbiwater/i;

function hashId(...parts: string[]): string {
  return createHash("sha1").update(parts.join("|")).digest("hex");
}

/**
 * `"20th February 2026"` / `"20 th February 2026"` / `"03 October 2024"` →
 * `"2026-02-20"`. `null` si aucune date reconnaissable. **Pure.**
 */
export function parseNwDate(raw: string): string | null {
  const re = new RegExp(RE_DATE.source, "i");
  const m = raw.match(re);
  if (!m) return null;
  const day = Number(m[1]);
  const month = MONTHS[m[2].toLowerCase()];
  const year = Number(m[3]);
  if (month === undefined || day < 1 || day > 31) return null;
  return `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

/**
 * Jeton horaire `"06:00 am"` / `"6:00am"` / `"12:00 pm"` → `"HH:MM"` (24 h).
 * Midi `12 pm` → `12:00`, minuit `12 am` → `00:00`. `null` si invalide. **Pure.**
 */
export function parseNwTime(raw: string): string | null {
  const re = new RegExp(RE_TIME.source, "i");
  const m = raw.match(re);
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
 * Extrait la fenêtre d'interruption d'un texte d'intro. On collecte toutes les
 * dates et toutes les heures DANS L'ORDRE du document et on apparie par index :
 * 1re date+1re heure = début, 2e = fin. Cet appariement positionnel marche quel
 * que soit le phrasé (« from <date> at <time> to <date> at <time> » comme
 * « start at <time> on <date> up to <time> on <date> »). `endDate`/`endTime`
 * retombent sur le début s'il n'y a qu'une occurrence. `null` si pas de
 * date+heure exploitables. **Pure.**
 */
export function parseNwWindow(introText: string): NwWindow | null {
  const dates: string[] = [];
  for (const m of introText.matchAll(RE_DATE)) {
    const d = parseNwDate(m[0]);
    if (d) dates.push(d);
  }
  const times: string[] = [];
  for (const m of introText.matchAll(RE_TIME)) {
    const t = parseNwTime(m[0]);
    if (t) times.push(t);
  }
  if (!dates.length || !times.length) return null;
  return {
    startDate: dates[0],
    endDate: dates[1] ?? dates[0],
    startTime: times[0],
    endTime: times[1] ?? times[0],
  };
}

/**
 * Découpe un texte en segments de puces : on ignore tout ce qui précède la 1re
 * « • » (préambule) puis on scinde sur « • ». Chaque segment est aplati
 * (retours ligne → espaces) et trimé. **Pure.**
 */
export function splitNwBullets(text: string): string[] {
  const i = text.indexOf("•");
  if (i < 0) return [];
  return text
    .slice(i)
    .split("•")
    .map((s) => s.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

/** Tronque un segment au premier marqueur de boilerplate (appel clients, signature, footer…). */
function stripBoilerplate(raw: string): string {
  const m = raw.match(RE_BOILERPLATE);
  return (m ? raw.slice(0, m.index) : raw).replace(/\s+/g, " ").trim();
}

/** Nettoie la ponctuation de queue d'une `reason`. */
function cleanReason(raw: string): string {
  return raw.replace(/\s+/g, " ").replace(/[\s,;]+$/, "").trim();
}

/** Nettoie un nom de zone : retire suffixes génériques (« areas », « and environs », « vicinity »…). */
function cleanQuartier(raw: string): string {
  return raw
    .replace(/\s+/g, " ")
    .replace(
      /\s*(?:and surrounding areas|and surrounding area|and surrounding environs|and environs|diplomatic areas?|areas?|vicinity)\s*$/i,
      ""
    )
    .replace(/[\s,;.]+$/, "")
    .trim();
}

/**
 * Détecte une mise en page 2 colonnes : au moins 2 marqueurs « • » dont le
 * centre tombe dans la moitié DROITE de la page. Sinon → mono-colonne. **Pure.**
 */
export function isTwoColumn(pages: KplcPage[]): boolean {
  for (const pg of pages) {
    const split = pg.width / 2;
    let right = 0;
    for (const it of pg.items) {
      if (it.str.includes("•") && (it.x0 + it.x1) / 2 >= split) right++;
    }
    if (right >= 2) return true;
  }
  return false;
}

/**
 * Reconstruit le texte des PUCES pour une notice 2 colonnes : on sépare les
 * items par moitié de page (centre < ou ≥ milieu), on RÉUTILISE
 * `reconstructText` sur chaque colonne isolée (plus aucune gouttière à
 * détecter → ordre haut-vers-bas fiable), on retire le préambule de CHAQUE
 * colonne (avant sa 1re « • ») pour éviter que le boilerplate/en-tête d'une
 * colonne contamine l'autre, puis on concatène. **Pure.**
 */
export function reconstructNwColumns(pages: KplcPage[]): string {
  const parts: string[] = [];
  for (const pg of pages) {
    const split = pg.width / 2;
    const halves: KplcTextItem[][] = [[], []];
    for (const it of pg.items) {
      const center = (it.x0 + it.x1) / 2;
      halves[center < split ? 0 : 1].push(it);
    }
    for (const items of halves) {
      if (!items.length) continue;
      const txt = reconstructText([{ width: pg.width, items }]);
      const i = txt.indexOf("•");
      if (i >= 0) parts.push(txt.slice(i));
    }
  }
  return parts.join("\n");
}

/**
 * Transforme les PDF bruts (déjà extraits par pdfjs) en schéma canonique.
 * **Fonction pure** (aucune I/O) :
 *   - lit la fenêtre horaire dans l'intro (texte reconstruit en lecture simple,
 *     le paragraphe d'intro y est contigu) ;
 *   - reconstruit les puces (2 colonnes si détecté, sinon mono-colonne) et
 *     mappe chaque puce structurée « <zone> — <rues> » → une coupure ;
 *   - sur l'ancien format « prose » (pas de tiret) : une coupure par puce,
 *     quartier = label court, reason = texte de la puce ;
 *   - ignore les puces sans zone/fenêtre exploitable ;
 *   - déduplique le lot par `rawHash` (upsert idempotent).
 */
export function normalizeNairobiWater(raw: RawKplcPdf[]): CanonicalOutage[] {
  const byHash = new Map<string, CanonicalOutage>();
  for (const pdf of raw) {
    // 1) Fenêtre horaire : paragraphe d'intro contigu dans la lecture simple.
    const plain = reconstructText(pdf.pages);
    const introEnd = plain.indexOf("•");
    const introText = introEnd >= 0 ? plain.slice(0, introEnd) : plain;
    const win = parseNwWindow(introText);
    if (!win) continue; // pas de fenêtre → notice inexploitable

    const startsAt = new Date(`${win.startDate}T${win.startTime}:00${NW_TZ_OFFSET}`);
    const endsAt = new Date(`${win.endDate}T${win.endTime}:00${NW_TZ_OFFSET}`);
    if (isNaN(startsAt.getTime()) || isNaN(endsAt.getTime())) continue;

    // 2) Puces : 2 colonnes (format riche) ou mono-colonne (ancien format).
    const bulletsText = isTwoColumn(pdf.pages)
      ? reconstructNwColumns(pdf.pages)
      : plain;

    for (const rawSeg of splitNwBullets(bulletsText)) {
      // On retire d'abord le boilerplate de queue : un footer « Toll Free
      // number – 0800724366 » contient un tiret espacé qui ferait sinon passer
      // une puce « prose » pour une puce structurée.
      const seg = stripBoilerplate(rawSeg);
      if (!seg) continue;
      const dash = seg.match(RE_DASH);
      let quartier: string;
      let reason: string;
      if (dash && dash.index !== undefined) {
        // Format structuré « <zone> — <rues> » (1er tiret entouré d'espaces).
        quartier = cleanQuartier(seg.slice(0, dash.index));
        reason = cleanReason(seg.slice(dash.index + dash[0].length));
      } else {
        // Ancien format « prose » : label court + texte entier de la puce.
        reason = cleanReason(seg);
        if (!reason) continue;
        const firstComma = reason.indexOf(",");
        const label = firstComma > 0 ? reason.slice(0, firstComma) : reason;
        quartier = cleanQuartier(label).slice(0, 80).trim();
      }
      if (!quartier) continue;

      const rawHash = hashId(
        "nairobi_water",
        quartier,
        win.startDate,
        win.startTime,
        win.endTime
      );
      if (byHash.has(rawHash)) continue; // dédup intra-lot

      byHash.set(rawHash, {
        provider: "nairobi_water",
        service: "water",
        country: "KE",
        region: "NAIROBI",
        ville: "NAIROBI",
        quartier,
        reason,
        progDate: win.startDate,
        startTime: win.startTime,
        endTime: win.endTime,
        startsAt,
        endsAt,
        rawHash,
        sourceUrl: pdf.sourceUrl,
      });
    }
  }
  return [...byHash.values()];
}

/** Titre d'un média (l'API renvoie soit une string, soit `{ rendered }`). */
function mediaTitle(it: NwMediaItem): string {
  if (typeof it.title === "string") return it.title;
  return it.title?.rendered ?? "";
}

/**
 * Filtre les médias WordPress pour ne garder que les PDF de notices
 * d'interruption, triés du plus récent au plus ancien (la `date` d'upload sert
 * uniquement de proxy de récence). Exclut les PDF hors-sujet (ex. « banking
 * services »). **Pure.**
 */
export function discoverNwPdfUrls(
  items: NwMediaItem[],
  max = NW_DEFAULT_MAX_PDFS
): string[] {
  const keep = items.filter((it) => {
    const url = (it.source_url ?? "").toLowerCase();
    if (!url.endsWith(".pdf")) return false;
    const hay = `${url} ${mediaTitle(it).toLowerCase()}`;
    if (!hay.includes("interruption")) return false;
    if (hay.includes("banking")) return false; // faux positif connu
    return true;
  });
  keep.sort((a, b) => (b.date ?? "").localeCompare(a.date ?? ""));
  const seen = new Set<string>();
  const urls: string[] = [];
  for (const it of keep) {
    const url = it.source_url!;
    if (seen.has(url)) continue;
    seen.add(url);
    urls.push(url);
    if (urls.length >= max) break;
  }
  return urls;
}

export class NairobiWaterAdapter implements OutageSourceAdapter {
  readonly provider = "nairobi_water";
  readonly country = "KE";

  constructor(private readonly maxPdfs = NW_DEFAULT_MAX_PDFS) {}

  /** Découvre les URLs des PDF les plus récents via l'API WordPress (I/O réseau). */
  async discover(): Promise<string[]> {
    const res = await fetch(NAIROBI_WATER_MEDIA_API, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; NjukaBot/1.0)" },
    });
    if (!res.ok) throw new Error(`Nairobi Water media API: HTTP ${res.status}`);
    const items = (await res.json()) as NwMediaItem[];
    return discoverNwPdfUrls(Array.isArray(items) ? items : [], this.maxPdfs);
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
      console.warn("NairobiWaterAdapter: échec découverte des PDF (ignorée)", e);
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
        console.warn(`NairobiWaterAdapter: échec PDF ${url} (ignoré)`, e);
      }
    }
    return out;
  }

  normalize(raw: RawKplcPdf[]): CanonicalOutage[] {
    return normalizeNairobiWater(raw);
  }
}
