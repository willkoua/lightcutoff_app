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

/**
 * Titre + corps de la notification « le service est revenu » envoyée aux
 * confirmeurs d'une coupure quand elle passe en `resolved`. Pur et testable.
 */
export function resolvedNotifContent(
  serviceType: string | undefined,
  area?: NotifArea
): { title: string; body: string } {
  const isWater = serviceType === "water";
  const title = isWater ? "L'eau est revenue 💧" : "Le courant est revenu ⚡";
  const parts = (area ? [area.neighborhood, area.city] : []).filter(
    (s): s is string => !!s && s.length > 0
  );
  const zone = parts.length > 0 ? ` à ${parts.join(", ")}` : "";
  const body = `Des voisins confirment le retour du service${zone}.`;
  return { title, body };
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

/** Bornes du rayon d'impact affiché sur la carte (agrégat anonyme). */
export const IMPACT_MIN_M = 150;
export const IMPACT_MAX_M = 2000;

/**
 * Rayon d'impact d'un report après une nouvelle confirmation (pur, testable).
 *
 * Le rayon stocké est la plus grande distance épicentre↔confirmeur observée,
 * bornée à [IMPACT_MIN_M, IMPACT_MAX_M] : le plancher donne une taille
 * lisible aux coupures peu confirmées, le plafond évite qu'une confirmation
 * aberrante (GPS erratique, repli device) ne dessine une tache absurde.
 * Ne décroît jamais — l'emprise d'une coupure ne rétrécit pas.
 */
export function nextImpactRadius(
  current: number | undefined,
  distanceM: number
): number {
  const sane = Number.isFinite(distanceM) && distanceM >= 0 ? distanceM : 0;
  const clamped = Math.min(Math.max(sane, IMPACT_MIN_M), IMPACT_MAX_M);
  return Math.round(Math.max(current ?? 0, clamped));
}

// ---------------------------------------------------------------------------
// Cycle de vie des signalements — ping « Toujours coupé ? » + expiration
// (décisions 2026-08-09 : ping unique à 4 h dans la fenêtre 7 h-21 h locale,
// expiration silencieuse à 48 h d'inactivité, constantes ajustables).
// ---------------------------------------------------------------------------

export const PING_AFTER_MS = 4 * 3600 * 1000;
export const EXPIRE_AFTER_MS = 48 * 3600 * 1000;
export const PING_WINDOW_START_H = 7; // heure locale incluse
export const PING_WINDOW_END_H = 21; // heure locale exclue
/** Décalage horaire du pays (heures vs UTC) — CM/WAT = UTC+1. */
export const COUNTRY_UTC_OFFSET_H: Record<string, number> = { CM: 1 };

/** L'heure locale du pays est-elle dans la fenêtre de ping 7 h-21 h ? */
export function inPingWindow(nowMs: number, countryCode?: string): boolean {
  const offset = COUNTRY_UTC_OFFSET_H[countryCode ?? ""] ?? 1;
  const localH = (Math.floor(nowMs / 3600000) + offset) % 24;
  return localH >= PING_WINDOW_START_H && localH < PING_WINDOW_END_H;
}

/** Une coupure inactive doit-elle expirer ? (dernière activité > 48 h) */
export function shouldExpire(lastActivityMs: number, nowMs: number): boolean {
  return nowMs - lastActivityMs >= EXPIRE_AFTER_MS;
}

/** Une coupure est-elle éligible au ping ? (âgée ≥ 4 h, fenêtre horaire ok) */
export function pingEligible(
  reportedAtMs: number,
  nowMs: number,
  countryCode?: string
): boolean {
  return nowMs - reportedAtMs >= PING_AFTER_MS && inPingWindow(nowMs, countryCode);
}

/** Contenu de la notification de ping (par service). */
export function stillOutPingContent(serviceType: string | undefined): {
  title: string;
  body: string;
} {
  const isWater = serviceType === "water";
  return {
    title: isWater ? "L'eau est-elle revenue ? 💧" : "Le courant est-il revenu ? ⚡",
    body: "Dis-le à tes voisins en un geste : toujours coupé, ou c'est revenu ?",
  };
}

// ---------------------------------------------------------------------------
// Boucle du signaleur (v67) — notif à l'auteur à la confirmation.
// ---------------------------------------------------------------------------

/** Faut-il notifier l'auteur pour cette N-ième confirmation ? (1ʳᵉ puis 5ᵉ) */
export function shouldNotifyAuthor(confirmationCount: number): boolean {
  return confirmationCount === 1 || confirmationCount === 5;
}

/** Contenu de la notif « tu n'es pas seul » à l'auteur. */
export function authorConfirmedContent(
  confirmationCount: number,
  area?: NotifArea
): { title: string; body: string } {
  const parts = (area ? [area.neighborhood, area.city] : []).filter(
    (s): s is string => !!s && s.length > 0
  );
  const zone = parts.length > 0 ? ` à ${parts.join(", ")}` : "";
  const who =
    confirmationCount === 1 ? "Un voisin confirme" : `${confirmationCount} voisins confirment`;
  return {
    title: "Tu n'es pas seul 🤝",
    body: `${who} ta coupure${zone}. Ton signalement aide le quartier.`,
  };
}

/** Ligne d'impact ajoutée à la notif de rétablissement des confirmeurs. */
export function impactLine(notifiedCount: number): string {
  if (notifiedCount <= 0) return "";
  return notifiedCount === 1
    ? " Ta confirmation a aidé à alerter 1 voisin."
    : ` Ta confirmation a aidé à alerter ${notifiedCount} voisins.`;
}
