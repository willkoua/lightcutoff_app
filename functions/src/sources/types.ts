/**
 * Contrats communs à l'ingestion de coupures **officielles planifiées** depuis
 * les fournisseurs d'électricité (Eneo aujourd'hui, autres pays demain).
 *
 * Chaque fournisseur fournit un adaptateur qui sait récupérer ses données
 * brutes (`fetch`, I/O réseau) puis les ramener au **schéma canonique**
 * (`normalize`, fonction **pure** sans I/O → testable sans réseau).
 */

/** Coupure officielle planifiée, indépendante du fournisseur. */
export interface CanonicalOutage {
  provider: string; // ex. "eneo"
  country: string; // ISO-3166-1 alpha-2, ex. "CM"
  region: string;
  ville: string;
  quartier: string;
  reason: string; // motif des travaux
  progDate: string; // date locale du fournisseur, YYYY-MM-DD
  startTime: string; // heure locale de début, HH:MM (affichage sans calcul de fuseau)
  endTime: string; // heure locale de fin, HH:MM
  startsAt: Date; // instant absolu (UTC)
  endsAt: Date;
  rawHash: string; // id stable → upsert idempotent + dédup
  sourceUrl: string;
}

/** Contrat d'un fournisseur de coupures officielles. */
export interface OutageSourceAdapter {
  readonly provider: string;
  readonly country: string;
  /** Récupère les données brutes (I/O réseau, résilient par sous-source). */
  fetch(): Promise<unknown[]>;
  /** Ramène les données brutes au schéma canonique. **Pur, sans I/O.** */
  normalize(raw: unknown[]): CanonicalOutage[];
}
