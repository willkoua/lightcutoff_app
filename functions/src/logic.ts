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
  return restorations >= resolutionThreshold(confirmations);
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
