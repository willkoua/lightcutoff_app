import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/official_outage.dart';
import '../repositories/official_outage_repository.dart';
import '../services/official_outage_service.dart';

/// État de l'écran « Coupures planifiées » : chargement one-shot + filtre région
/// et recherche quartier appliqués côté client. Créé à l'ouverture de l'écran
/// (lazy), pas dans le MultiProvider global.
class OfficialOutageProvider extends ChangeNotifier {
  OfficialOutageProvider({
    required String country,
    OfficialOutageRepository? repository,
  }) : _country = country,
       _repo = repository ?? OfficialOutageService() {
    load();
  }

  final OfficialOutageRepository _repo;
  String _country;

  /// Pays (ISO) actuellement requêté.
  String get country => _country;

  /// Change le pays et recharge (no-op si identique).
  void setCountry(String country) {
    if (country == _country) return;
    _country = country;
    load();
  }

  List<OfficialOutage> _all = [];
  bool _loading = true;
  bool _error = false;
  String _query = '';
  String? _region; // null = toutes les régions
  String? _ville; // null = toutes les villes (cascade sous la région)
  ServiceType?
  _serviceFilter; // null = tous services (alimenté par RegionProvider)

  bool get loading => _loading;
  bool get hasError => _error;
  String get query => _query;
  String? get region => _region;
  String? get ville => _ville;
  ServiceType? get serviceFilter => _serviceFilter;

  /// Régions distinctes présentes dans la donnée (pour le filtre), triées.
  /// Calculées sur le sous-ensemble du service actif pour rester cohérent
  /// avec la liste affichée (pas de région fantôme d'un service masqué).
  List<String> get regions {
    final base =
        _serviceFilter == null
            ? _all
            : _all.where((o) => o.serviceType == _serviceFilter);
    return base.map((o) => o.region).where((r) => r.isNotEmpty).toSet().toList()
      ..sort();
  }

  /// Villes distinctes présentes dans la donnée (pour le filtre ville), triées.
  /// Cascade sous la région sélectionnée : si une région est choisie, seules
  /// ses villes sont proposées. Tient compte du service actif pour rester
  /// cohérent avec la liste affichée.
  List<String> get villes {
    return _all
        .where((o) => _serviceFilter == null || o.serviceType == _serviceFilter)
        .where((o) => _region == null || o.region == _region)
        .map((o) => o.ville)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  /// Liste filtrée par service + région + recherche (quartier ou ville).
  List<OfficialOutage> get filtered {
    final q = _query.trim().toLowerCase();
    return _all.where((o) {
      if (_serviceFilter != null && o.serviceType != _serviceFilter) {
        return false;
      }
      if (_region != null && o.region != _region) return false;
      if (_ville != null && o.ville != _ville) return false;
      if (q.isNotEmpty &&
          !o.quartier.toLowerCase().contains(q) &&
          !o.ville.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> load() async {
    _loading = true;
    _error = false;
    notifyListeners();
    try {
      _all = await _repo.fetchUpcoming(country: _country);
    } catch (_) {
      _error = true;
    }
    _loading = false;
    notifyListeners();
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setRegion(String? region) {
    if (region == _region) return;
    _region = region;
    // La ville sélectionnée peut ne plus exister sous la nouvelle région →
    // on la réinitialise pour éviter un filtre fantôme (liste vide muette).
    if (_ville != null && !villes.contains(_ville)) _ville = null;
    notifyListeners();
  }

  void setVille(String? ville) {
    if (ville == _ville) return;
    _ville = ville;
    notifyListeners();
  }

  /// Aligne le filtre service sur celui de [RegionProvider.serviceFilter].
  /// `null` = toutes les coupures planifiées (tous services). En l'absence
  /// d'adaptateur d'ingestion CAMWATER, sélectionner `water` produira un
  /// état vide — comportement attendu (cf. `tasks/TESTS-MANUELS.md`).
  void setServiceFilter(ServiceType? value) {
    if (value == _serviceFilter) return;
    _serviceFilter = value;
    // Région/ville peuvent ne plus exister dans le nouveau périmètre service.
    if (_region != null && !regions.contains(_region)) _region = null;
    if (_ville != null && !villes.contains(_ville)) _ville = null;
    notifyListeners();
  }
}
