/**
 * Logique métier **pure** des Cloud Functions, isolée des I/O Firestore/FCM
 * pour être testable sans émulateur. Les triggers de `index.ts` orchestrent
 * les lectures/écritures et délèguent les décisions ici.
 */

/**
 * Constantes d'auto-résolution crowd-sourcée.
 * ⚠️ DOIVENT rester alignées avec `AppConstants.restorationMinVotes` /
 * `restorationRatio` côté Dart (`lib/config/app_constants.dart`).
 */
export const RESTORATION_MIN_VOTES = 3;
export const RESTORATION_RATIO = 0.5;

/**
 * Plancher de votes **effectif**, surchargeable par la variable d'environnement
 * `RESTORATION_MIN_VOTES` (fixée par projet via `functions/.env.<projet>`).
 * Sert à abaisser temporairement le seuil en staging pour tester le flux à un
 * seul compte, **sans toucher le défaut prod-sûr de 3** ni les tests purs
 * (env non défini → renvoie [RESTORATION_MIN_VOTES]).
 */
export function effectiveMinVotes(): number {
  const raw = process.env.RESTORATION_MIN_VOTES;
  const n = raw ? Number.parseInt(raw, 10) : NaN;
  return Number.isFinite(n) && n >= 1 ? n : RESTORATION_MIN_VOTES;
}

/** Zone lisible utilisée pour composer le corps de la notification. */
export interface NotifArea {
  neighborhood?: string;
  city?: string;
}

/** Données d'un report nécessaires à la décision d'auto-résolution. */
export interface ResolutionInput {
  status?: string;
  archivedAt?: unknown;
  confirmationCount?: number;
  restorationCount?: number;
}

/**
 * Seuil de déclarations « courant revenu » à atteindre pour auto-résoudre une
 * coupure, étant donné son nombre de confirmations :
 *   max(minVotes, ceil(confirmations × ratio)).
 * Le plancher évite qu'une poignée de votes ferme une coupure très confirmée.
 */
export function resolutionThreshold(
  confirmations: number,
  minVotes: number = RESTORATION_MIN_VOTES,
  ratio: number = RESTORATION_RATIO
): number {
  return Math.max(minVotes, Math.ceil(confirmations * ratio));
}

/**
 * Décide si un report doit passer en `resolved`. Faux si déjà résolu, archivé,
 * ou si le nombre de restorations n'atteint pas [resolutionThreshold].
 */
export function shouldResolve(report: ResolutionInput): boolean {
  if (report.status === "resolved") return false;
  if (report.archivedAt) return false;
  const confirmations = report.confirmationCount ?? 0;
  const restorations = report.restorationCount ?? 0;
  return restorations >= resolutionThreshold(confirmations, effectiveMinVotes());
}

/**
 * Alphabet base32 du geohash (identique à `lib/utils/geohash.dart`).
 */
const GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/** Centre (lat/lng) d'une cellule geohash. */
export interface LatLng {
  lat: number;
  lng: number;
}

/**
 * Décode un geohash vers le **centre** de sa cellule. Inverse de
 * `encodeGeohash` côté Dart — même alphabet, longitude en premier. Renvoie
 * `null` si la chaîne est vide ou contient un caractère hors alphabet.
 */
export function decodeGeohashCenter(hash: string): LatLng | null {
  if (!hash) return null;
  let latMin = -90,
    latMax = 90,
    lngMin = -180,
    lngMax = 180;
  let even = true; // longitude en premier
  for (const ch of hash) {
    const idx = GEOHASH_BASE32.indexOf(ch);
    if (idx < 0) return null;
    for (let bit = 4; bit >= 0; bit--) {
      const isOne = ((idx >> bit) & 1) === 1;
      if (even) {
        const mid = (lngMin + lngMax) / 2;
        if (isOne) lngMin = mid;
        else lngMax = mid;
      } else {
        const mid = (latMin + latMax) / 2;
        if (isOne) latMin = mid;
        else latMax = mid;
      }
      even = !even;
    }
  }
  return { lat: (latMin + latMax) / 2, lng: (lngMin + lngMax) / 2 };
}

/** Bounding box de l'emprise mesurée d'une coupure. */
export interface ImpactBounds {
  impactMinLat: number;
  impactMaxLat: number;
  impactMinLng: number;
  impactMaxLng: number;
}

/**
 * Étend une bounding box d'impact pour inclure [point]. Si [current] est absente
 * ou incomplète, on repart de [point] (box dégénérée). Croissance monotone : une
 * emprise ne rétrécit jamais (une coupure ne « dé-s'étend » pas).
 */
export function expandImpactBounds(
  current: Partial<ImpactBounds> | null | undefined,
  point: LatLng
): ImpactBounds {
  const has =
    current != null &&
    typeof current.impactMinLat === "number" &&
    typeof current.impactMaxLat === "number" &&
    typeof current.impactMinLng === "number" &&
    typeof current.impactMaxLng === "number";
  if (!has) {
    return {
      impactMinLat: point.lat,
      impactMaxLat: point.lat,
      impactMinLng: point.lng,
      impactMaxLng: point.lng,
    };
  }
  const c = current as ImpactBounds;
  return {
    impactMinLat: Math.min(c.impactMinLat, point.lat),
    impactMaxLat: Math.max(c.impactMaxLat, point.lat),
    impactMinLng: Math.min(c.impactMinLng, point.lng),
    impactMaxLng: Math.max(c.impactMaxLng, point.lng),
  };
}

/** Construit le corps de la notif à partir de la zone du report. */
export function buildBody(area?: NotifArea): string {
  const fallback = "Une coupure vient d'être signalée près de chez vous.";
  if (!area) return fallback;
  const parts = [area.neighborhood, area.city].filter(
    (s): s is string => !!s && s.length > 0
  );
  if (parts.length === 0) return fallback;
  return `${parts.join(", ")} · à l'instant`;
}

/** Entrée pour composer le corps d'une alerte de coupure planifiée. */
export interface PlannedAlertInput {
  quartier?: string;
  startTime?: string; // HH:MM local
  endTime?: string;
}

/**
 * Corps de la notification « coupure planifiée demain » (FR). Pur et testable.
 */
export function plannedAlertBody(input: PlannedAlertInput): string {
  const q = (input.quartier ?? "").trim() || "votre quartier";
  const s = (input.startTime ?? "").trim();
  const e = (input.endTime ?? "").trim();
  const window = s && e ? ` de ${s} à ${e}` : "";
  return `Coupure planifiée demain à ${q}${window}.`;
}
