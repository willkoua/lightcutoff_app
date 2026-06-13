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
  }

  static const _prefKey = 'provider_override_id';

  ElectricityProvider? _override; // dev, persistant
  String? _homeCountryIso; // dérivé de homeLocation du profil

  bool get isOverridden => _override != null;
  ElectricityProvider? get overrideProvider => _override;

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
