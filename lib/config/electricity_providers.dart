/// Compagnies d'électricité couvertes par l'app, rattachées à un pays.
///
/// Ajouter un pays/compagnie = **une entrée** dans [kSupportedProviders]
/// (aligné avec l'adaptateur backend `functions/src/sources/`). Le champ
/// `country` (ISO-3166-1 alpha-2) sert à filtrer `official_outages`.
class ElectricityProvider {
  const ElectricityProvider({
    required this.id,
    required this.country,
    required this.label,
    required this.countryLabel,
    this.countryAliases = const [],
  });

  /// Identifiant stable, == champ `provider` des docs `official_outages`.
  final String id;

  /// Code pays ISO-3166-1 alpha-2 (ex. `CM`).
  final String country;

  /// Nom de la compagnie (ex. `Eneo`).
  final String label;

  /// Nom du pays affiché (ex. `Cameroun`).
  final String countryLabel;

  /// Noms de pays (localisés) servant à matcher `homeLocation.country`
  /// (qui contient un nom libre issu du reverse-géocodage, pas un code ISO).
  final List<String> countryAliases;

  /// Libellé d'affichage, ex. « Eneo · Cameroun ».
  String get displayLabel => '$label · $countryLabel';
}

/// Fournisseurs supportés. **Source unique** côté app.
const List<ElectricityProvider> kSupportedProviders = [
  ElectricityProvider(
    id: 'eneo',
    country: 'CM',
    label: 'Eneo',
    countryLabel: 'Cameroun',
    countryAliases: ['cameroun', 'cameroon'],
  ),
];

/// Fournisseur supporté pour un code pays ISO, ou `null` si non couvert.
ElectricityProvider? providerForCountry(String? countryIso) {
  if (countryIso == null) return null;
  final c = countryIso.toUpperCase();
  for (final p in kSupportedProviders) {
    if (p.country == c) return p;
  }
  return null;
}

/// Résout un **nom** de pays libre (ex. « Cameroun » venant de `homeLocation`)
/// en code ISO supporté, via les alias. `null` si non reconnu.
String? isoFromCountryName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final n = name.trim().toLowerCase();
  for (final p in kSupportedProviders) {
    if (p.countryLabel.toLowerCase() == n) return p.country;
    if (p.countryAliases.contains(n)) return p.country;
  }
  return null;
}
