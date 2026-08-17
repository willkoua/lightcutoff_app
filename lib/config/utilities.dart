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

  /// Nom de la compagnie (ex. `SOCADEL`, `CAMWATER`).
  final String label;

  /// Nom du pays affiché (ex. `Cameroun`).
  final String countryLabel;

  /// Noms de pays (localisés) servant à matcher `homeLocation.country`
  /// (qui contient un nom libre issu du reverse-géocodage, pas un code ISO).
  final List<String> countryAliases;

  /// Libellé d'affichage, ex. « SOCADEL · Cameroun ».
  String get displayLabel => '$label · $countryLabel';
}

/// Fournisseurs EMBARQUÉS — filet de sécurité hors-ligne / premier démarrage.
/// Depuis le 2026-08-13, la **source de vérité est la collection Firestore
/// `utilities`** (lecture publique, écriture Admin SDK) : au démarrage,
/// [applyRemoteUtilities] fusionne le remote PAR-DESSUS cette liste
/// (surcharge par `id`, ajout des nouveaux, retrait des `enabled: false`).
/// Ajouter un pays/compagnie = **un document Firestore**, sans release.
/// Cette liste embarquée ne doit contenir que le socle (Cameroun) et n'est
/// JAMAIS prioritaire sur le remote quand il est disponible.
const List<Utility> kSupportedUtilities = [
  Utility(
    // ⚠️ `id` reste 'eneo' malgré le renommage commercial Eneo → SOCADEL :
    // il est persisté (SharedPreferences overrides) et aligné sur le champ
    // `provider` des docs `official_outages` — le changer orphelinerait les
    // deux. Seul le libellé affiché change.
    id: 'eneo',
    service: ServiceType.electricity,
    country: 'CM',
    label: 'SOCADEL',
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
  // RD Congo (SNEL élec + REGIDESO eau) retirée le 2026-07-25 avant le
  // lancement prod : on ne liste pas un pays sans présence réelle. Le modèle
  // multi-pays reste en place — ré-ajouter une entrée [Utility] suffit.
];

/// Registre ACTIF : embarqué au démarrage, remplacé par la fusion
/// embarqué + remote dès que la collection `utilities` a répondu.
List<Utility> _active = kSupportedUtilities;

/// Liste active des fournisseurs (embarqué ⊕ remote). C'est CETTE liste que
/// toutes les résolutions lisent — jamais [kSupportedUtilities] directement.
List<Utility> get supportedUtilities => _active;

/// Fusionne le catalogue remote par-dessus l'embarqué :
/// - un doc remote au même `id` **remplace** l'entrée embarquée ;
/// - un `id` inconnu est **ajouté** (nouveaux pays sans release) ;
/// - un `id` présent dans [disabledIds] est **retiré** (y compris embarqué).
/// Pure et sans I/O → testable. Renvoie la liste fusionnée (ordre : embarqué
/// d'abord, ajouts remote ensuite).
List<Utility> mergeUtilities(
  List<Utility> bundled,
  List<Utility> upserts, {
  Set<String> disabledIds = const {},
}) {
  final byId = <String, Utility>{for (final u in bundled) u.id: u};
  final order = [for (final u in bundled) u.id];
  for (final u in upserts) {
    if (!byId.containsKey(u.id)) order.add(u.id);
    byId[u.id] = u;
  }
  return [
    for (final id in order)
      if (!disabledIds.contains(id)) byId[id]!,
  ];
}

/// Applique le catalogue remote (appelé par RegionProvider au démarrage).
void applyRemoteUtilities(
  List<Utility> upserts, {
  Set<String> disabledIds = const {},
}) {
  _active = mergeUtilities(
    kSupportedUtilities,
    upserts,
    disabledIds: disabledIds,
  );
}

/// Réinitialise le registre à l'embarqué (isolation des tests).
void resetUtilities() => _active = kSupportedUtilities;

/// Tous les fournisseurs d'un pays (toutes services confondus).
List<Utility> utilitiesForCountry(String? countryIso) {
  if (countryIso == null) return const [];
  final c = countryIso.toUpperCase();
  return [
    for (final u in supportedUtilities)
      if (u.country == c) u,
  ];
}

/// Fournisseur supporté pour un couple (pays ISO, service), ou `null` si non
/// couvert.
Utility? utilityForCountryAndService(String? countryIso, ServiceType service) {
  if (countryIso == null) return null;
  final c = countryIso.toUpperCase();
  for (final u in supportedUtilities) {
    if (u.country == c && u.service == service) return u;
  }
  return null;
}

/// Un pays couvert par l'app (code ISO + libellé affichable).
class SupportedCountry {
  const SupportedCountry(this.iso, this.label);
  final String iso;
  final String label;
}

/// Pays **distincts** couverts par l'app (dérivés de [kSupportedUtilities]),
/// pour alimenter le sélecteur de pays utilisateur. Dédupliqués par ISO,
/// ordre d'apparition préservé.
List<SupportedCountry> supportedCountries() {
  final seen = <String>{};
  final out = <SupportedCountry>[];
  for (final u in supportedUtilities) {
    if (seen.add(u.country)) {
      out.add(SupportedCountry(u.country, u.countryLabel));
    }
  }
  return out;
}

/// Libellé affichable d'un code pays ISO (ex. `CM` → « Cameroun »), ou `null`
/// si le pays n'est pas couvert (on affichera alors le code brut).
String? countryLabelForIso(String? iso) {
  if (iso == null) return null;
  final c = iso.toUpperCase();
  for (final u in supportedUtilities) {
    if (u.country == c) return u.countryLabel;
  }
  return null;
}

/// Résout un **nom** de pays libre (ex. « Cameroun » venant de `homeLocation`)
/// en code ISO supporté, via les alias. `null` si non reconnu.
String? isoFromCountryName(String? name) {
  if (name == null || name.trim().isEmpty) return null;
  final n = name.trim().toLowerCase();
  for (final u in supportedUtilities) {
    if (u.countryLabel.toLowerCase() == n) return u.country;
    if (u.countryAliases.contains(n)) return u.country;
  }
  return null;
}
