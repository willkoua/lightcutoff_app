import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/electricity_providers.dart';
import '../repositories/location_repository.dart';
import '../services/location_service.dart';

/// Détermine le **fournisseur d'électricité actif** (pays + compagnie) pour
/// aller chercher les coupures planifiées.
///
/// Priorité de résolution du pays :
///   1. **override dev** (persisté, caché en release)
///   2. **`homeLocation.country`** du profil (renseigné via le proxy AuthProvider)
///   3. **pays de la locale du téléphone** (sans permission)
///   4. défaut **`CM`**
class RegionProvider extends ChangeNotifier {
  RegionProvider({LocationRepository? location})
    : _location = location ?? LocationService() {
    _loadOverride();
    _loadWorldwide();
    _detectCountry();
  }

  static const _prefKey = 'provider_override_id';
  static const _worldwideKey = 'admin_worldwide';

  final LocationRepository _location;

  ElectricityProvider? _override; // dev, persistant
  String? _detectedCountryIso; // pays GPS (où se trouve l'utilisateur)
  String? _homeCountryIso; // dérivé de homeLocation du profil
  bool _worldwide = false; // admin : voir tous les signalements (tous pays)

  bool get isOverridden => _override != null;
  ElectricityProvider? get overrideProvider => _override;

  /// `true` = afficher les signalements du **monde entier** (réservé admin).
  /// Quand actif, le cloisonnement par pays est levé.
  bool get worldwide => _worldwide;

  Future<void> _loadOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefKey);
    if (id == null || id.isEmpty) return;
    for (final p in kSupportedProviders) {
      if (p.id == id) {
        _override = p;
        notifyListeners();
        return;
      }
    }
  }

  Future<void> _loadWorldwide() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_worldwideKey) ?? false;
    if (v != _worldwide) {
      _worldwide = v;
      notifyListeners();
    }
  }

  /// Active/désactive la vue monde (admin). Persisté.
  Future<void> setWorldwide(bool value) async {
    if (value == _worldwide) return;
    _worldwide = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_worldwideKey, value);
  }

  String? get _localeCountry =>
      PlatformDispatcher.instance.locale.countryCode?.toUpperCase();

  /// Détecte le pays via la **position GPS** (où se trouve l'utilisateur), si la
  /// localisation est déjà autorisée (best-effort, sans déclencher de demande).
  Future<void> _detectCountry() async {
    try {
      if (await _location.checkAccess() != LocationAccess.granted) return;
      final loc = await _location.getCurrentLocation();
      final iso = loc.area.countryCode.toUpperCase();
      if (iso.isNotEmpty && iso != _detectedCountryIso) {
        _detectedCountryIso = iso;
        notifyListeners();
      }
    } catch (_) {
      // best-effort : on garde la résolution par profil / locale.
    }
  }

  /// Pays actif (ISO), selon la priorité :
  /// override dev → **GPS** → pays du profil → locale → défaut CM.
  String get activeCountry {
    if (_override != null) return _override!.country;
    if (_detectedCountryIso != null) return _detectedCountryIso!;
    if (_homeCountryIso != null) return _homeCountryIso!;
    final loc = _localeCountry;
    if (loc != null && loc.isNotEmpty) return loc;
    return 'CM';
  }

  /// Compagnie active, ou `null` si le pays actif n'est pas (encore) couvert.
  ElectricityProvider? get activeProvider =>
      _override ?? providerForCountry(activeCountry);

  /// Mis à jour par le profil (`homeLocation.country`). Re-résout si ça change.
  void setHomeCountry(String? countryName) {
    final iso = isoFromCountryName(countryName);
    if (iso == _homeCountryIso) return;
    _homeCountryIso = iso;
    notifyListeners();
  }

  /// Override dev (`null` = auto). Persisté dans SharedPreferences.
  Future<void> setOverride(ElectricityProvider? provider) async {
    _override = provider;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (provider == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, provider.id);
    }
  }
}
