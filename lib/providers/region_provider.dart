import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/electricity_providers.dart';

/// Détermine le **fournisseur d'électricité actif** (pays + compagnie) pour
/// aller chercher les coupures planifiées.
///
/// Priorité de résolution du pays :
///   1. **override dev** (persisté, caché en release)
///   2. **`homeLocation.country`** du profil (renseigné via le proxy AuthProvider)
///   3. **pays de la locale du téléphone** (sans permission)
///   4. défaut **`CM`**
class RegionProvider extends ChangeNotifier {
  RegionProvider() {
    _loadOverride();
    _loadWorldwide();
  }

  static const _prefKey = 'provider_override_id';
  static const _worldwideKey = 'admin_worldwide';

  ElectricityProvider? _override; // dev, persistant
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

  /// Pays actif (ISO), selon la priorité.
  String get activeCountry {
    if (_override != null) return _override!.country;
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
