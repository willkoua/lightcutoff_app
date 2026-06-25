import '../models/enums.dart';

/// Compagnies de service public couvertes par l'app, rattachées à un pays
/// et à un [ServiceType] (électricité, eau). Modèle unifié introduit avec
/// le pivot multi-service 2026-06-24 — remplace l'ancien
/// `ElectricityProvider` (mono-service).
///
/// Ajouter un pays/compagnie = **une entrée** dans [kSupportedUtilities],
/// aligné avec les adaptateurs backend `functions/src/sources/`. Le champ
/// `country` (ISO-3166-1 alpha-2) sert à filtrer `official_outages`.
class Utility {
  const Utility({
    required this.id,
    required this.service,
    required this.country,
    required this.label,
    required this.countryLabel,
    this.countryAliases = const [],
  });

  /// Identifiant stable, == champ `provider` des docs `official_outages`.
  final String id;

  /// Service public couvert (électricité / eau).
  final ServiceType service;

  /// Code pays ISO-3166-1 alpha-2 (ex. `CM`).
  final String country;

  /// Nom de la compagnie (ex. `Eneo`, `CAMWATER`).
  final String label;

  /// Nom du pays affiché (ex. `Cameroun`).
  final String countryLabel;

  /// Noms de pays (localisés) servant à matcher `homeLocation.country`
  /// (qui contient un nom libre issu du reverse-géocodage, pas un code ISO).
  final List<String> countryAliases;

  /// Libellé d'affichage, ex. « Eneo · Cameroun ».
  String get displayLabel => '$label · $countryLabel';
}

/// Fournisseurs supportés (tous services confondus). **Source unique** côté
/// app.
const List<Utility> kSupportedUtilities = [
  Utility(
    id: 'eneo',
    service: ServiceType.electricity,
    country: 'CM',
    label: 'Eneo',
    countryLabel: 'Cameroun',
    countryAliases: ['cameroun', 'cameroon'],
  ),
  Utility(
    id: 'camwater',
    service: ServiceType.water,
    country: 'CM',
    label: 'CAMWATER',
    countryLabel: 'Cameroun',
    countryAliases: ['cameroun', 'cameroon'],
  ),
];

/// Tous les fournisseurs d'un pays (toutes services confondus).
List<Utility> utilitiesForCountry(String? countryIso) {
  if (countryIso == null) return const [];
  final c = countryIso.toUpperCase();
  return [
    for (final u in kSupportedUtilities)
      if (u.country == c) u,
  ];
}

/// Fournisseur supporté pour un couple (pays ISO, service), ou `null` si non
/// couvert.
Utility? utilityForCountryAndService(String? countryIso, ServiceType service) {
  if (countryIso == null) return null;
  final c = countryIso.toUpperCase();
  for (final u in kSupportedUtilities) {
    if (u.country == c && u.service == service) return u;
  }
  return null;
}

/// Résout un **nom** de pays libre (ex. « Cameroun » venant de `homeLocation`)
/// en code ISO supporté, via les alias. `null` si non reconnu.
String? isoFromCountryName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final n = name.trim().toLowerCase();
  for (final u in kSupportedUtilities) {
    if (u.countryLabel.toLowerCase() == n) return u.country;
    if (u.countryAliases.contains(n)) return u.country;
  }
  return null;
}
