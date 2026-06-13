import 'package:flutter/foundation.dart';

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

  bool get loading => _loading;
  bool get hasError => _error;
  String get query => _query;
  String? get region => _region;

  /// Régions distinctes présentes dans la donnée (pour le filtre), triées.
  List<String> get regions =>
      _all.map((o) => o.region).where((r) => r.isNotEmpty).toSet().toList()
        ..sort();

  /// Liste filtrée par région + recherche (quartier ou ville).
  List<OfficialOutage> get filtered {
    final q = _query.trim().toLowerCase();
    return _all.where((o) {
      if (_region != null && o.region != _region) return false;
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
    _region = region;
    notifyListeners();
  }
}
