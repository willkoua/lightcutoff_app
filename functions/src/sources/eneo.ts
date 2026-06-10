/**
 * Adaptateur Eneo (Cameroun) — programme officiel des travaux & coupures.
 *
 * Source vérifiée en live (2026-06-10) :
 *   POST https://alert.eneo.cm/ajaxOutage.php   body: region=<1..10>
 *   → {"status":1,"data":[{observations, prog_date, prog_heure_debut,
 *      prog_heure_fin, region, ville, quartier}]}
 * Codes 1..10 = les 10 régions du Cameroun (ordre alphabétique) ; le nom de
 * région est dans la réponse. Heures locales **Africa/Douala = UTC+1 (pas de
 * DST)**. Contenu = **travaux planifiés** uniquement (≠ délestage quotidien).
 *
 * `normalizeEneo` est **pure** (aucune I/O) → testée dans `eneo.test.ts`.
 */
import { createHash } from "node:crypto";
import { CanonicalOutage, OutageSourceAdapter } from "./types";

export const ENEO_ENDPOINT = "https://alert.eneo.cm/ajaxOutage.php";
/** Codes région Eneo (1..10 = 10 régions CM, ordre alphabétique). */
export const ENEO_REGION_CODES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
/** Décalage horaire local Eneo (Africa/Douala = UTC+1, pas de DST). */
const ENEO_TZ_OFFSET = "+01:00";

/** Item brut tel que renvoyé par `ajaxOutage.php`. */
export interface RawEneoItem {
  observations?: string;
  prog_date?: string;
  prog_heure_debut?: string;
  prog_heure_fin?: string;
  region?: string;
  ville?: string;
  quartier?: string;
}

interface EneoResponse {
  status?: number;
  data?: RawEneoItem[];
}

function hashId(...parts: string[]): string {
  return createHash("sha1").update(parts.join("|")).digest("hex");
}

/**
 * Transforme les items bruts Eneo en schéma canonique. **Fonction pure.**
 * - nettoie les espaces parasites (« ` QUARTIER GENTIL` », « `  LOGBESSOU` ») ;
 * - ignore les entrées inexploitables (quartier vide, date ou fenêtre manquante,
 *   horaire invalide) ;
 * - déduplique le lot par `rawHash` (Eneo renvoie des doublons exacts).
 */
export function normalizeEneo(items: RawEneoItem[]): CanonicalOutage[] {
  const byHash = new Map<string, CanonicalOutage>();
  for (const it of items) {
    const region = (it.region ?? "").trim();
    const ville = (it.ville ?? "").trim();
    const quartier = (it.quartier ?? "").trim();
    const reason = (it.observations ?? "").trim();
    const progDate = (it.prog_date ?? "").trim();
    const debut = (it.prog_heure_debut ?? "").trim();
    const fin = (it.prog_heure_fin ?? "").trim();

    if (!quartier || !progDate || !debut || !fin) continue;

    const startsAt = new Date(`${progDate}T${debut}:00${ENEO_TZ_OFFSET}`);
    const endsAt = new Date(`${progDate}T${fin}:00${ENEO_TZ_OFFSET}`);
    if (isNaN(startsAt.getTime()) || isNaN(endsAt.getTime())) continue;

    const rawHash = hashId(
      "eneo",
      region,
      ville,
      quartier,
      progDate,
      debut,
      fin
    );
    if (byHash.has(rawHash)) continue; // dédup intra-lot

    byHash.set(rawHash, {
      provider: "eneo",
      country: "CM",
      region,
      ville,
      quartier,
      reason,
      progDate,
      startTime: debut,
      endTime: fin,
      startsAt,
      endsAt,
      rawHash,
      sourceUrl: ENEO_ENDPOINT,
    });
  }
  return [...byHash.values()];
}

export class EneoAdapter implements OutageSourceAdapter {
  readonly provider = "eneo";
  readonly country = "CM";

  /** Récupère les items bruts d'une région (I/O réseau). */
  async fetchRegion(code: number): Promise<RawEneoItem[]> {
    const res = await fetch(ENEO_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `region=${code}`,
    });
    if (!res.ok) throw new Error(`Eneo region ${code}: HTTP ${res.status}`);
    const json = (await res.json()) as EneoResponse;
    return json.data ?? [];
  }

  /**
   * Récupère toutes les régions. **Résilient par région** : un échec sur une
   * région est journalisé et ignoré (la donnée officielle est un bonus, jamais
   * une dépendance bloquante).
   */
  async fetch(): Promise<RawEneoItem[]> {
    const all: RawEneoItem[] = [];
    for (const code of ENEO_REGION_CODES) {
      try {
        all.push(...(await this.fetchRegion(code)));
      } catch (e) {
        console.warn(`EneoAdapter: échec région ${code} (ignorée)`, e);
      }
    }
    return all;
  }

  normalize(raw: RawEneoItem[]): CanonicalOutage[] {
    return normalizeEneo(raw);
  }
}
