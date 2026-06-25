import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/utilities.dart';
import '../models/enums.dart';
import '../repositories/location_repository.dart';
import '../services/location_service.dart';

/// Détermine le **fournisseur de service public actif** (pays + compagnie) pour
/// aller chercher les coupures planifiées et taguer les signalements.
///
/// Priorité de résolution du pays :
///   1. **override dev** (persisté, caché en release)
///   2. **GPS** (où se trouve l'utilisateur)
///   3. **`homeLocation.country`** du profil (renseigné via le proxy AuthProvider)
///   4. **pays de la locale du téléphone** (sans permission)
///   5. défaut **`CM`**
///
/// Multi-service (introduit avec le pivot 2026-06-24) : pour un même pays, on
/// expose un fournisseur **par service** ([activeUtility]). L'override dev,
/// quand posé, est lié à un service précis — il ne « remplace » donc que la
/// résolution de ce service-là.
class RegionProvider extends ChangeNotifier {
  RegionProvider({LocationRepository? location})
    : _location = location ?? LocationService() {
    _loadOverride();
    _loadWorldwide();
    _loadServiceFilter();
    _detectCountry();
  }

  // Nouvelles clés (pivot étape 3 — 1 override par service).
  static const _prefKeyElec = 'provider_override_electricity_id';
  static const _prefKeyWater = 'provider_override_water_id';
  // Clé héritée (avant la séparation par service). Migrée puis supprimée au
  // 1ʳᵉ chargement — voir `_loadOverride`.
  static const _legacyPrefKey = 'provider_override_id';
  static const _worldwideKey = 'admin_worldwide';
  static const _serviceFilterKey = 'service_filter';

  final LocationRepository _location;

  /// Override dev par service. `null` = résolution standard (GPS / profil /
  /// locale / défaut CM). Le picker des Paramètres expose UN champ par
  /// service ; sélectionner un fournisseur d'un pays X **aligne
  /// automatiquement** l'autre service sur le fournisseur du même pays
  /// (si présent dans `kSupportedUtilities`).
  Utility? _overrideElec;
  Utility? _overrideWater;

  String? _detectedCountryIso; // pays GPS (où se trouve l'utilisateur)
  String? _homeCountryIso; // dérivé de homeLocation du profil
  bool _worldwide = false; // admin : voir tous les signalements (tous pays)
  ServiceType? _serviceFilter; // null = Tout, sinon Élec ou Eau (persisté)

  /// Override pour un service donné, ou `null` (résolution standard).
  Utility? overrideUtility(ServiceType service) =>
      service == ServiceType.electricity ? _overrideElec : _overrideWater;

  /// `true` si AU MOINS un service est en override dev.
  bool get isOverridden => _overrideElec != null || _overrideWater != null;

  /// `true` si le service indiqué est en override.
  bool isOverriddenFor(ServiceType service) => overrideUtility(service) != null;

  /// `true` = afficher les signalements du **monde entier** (réservé admin).
  /// Quand actif, le cloisonnement par pays est levé.
  bool get worldwide => _worldwide;

  /// Filtre service actif pour les listes/cartes (`null` = Tout). Persisté
  /// dans SharedPreferences → rejoué au prochain lancement.
  ServiceType? get serviceFilter => _serviceFilter;

  Future<void> _loadOverride() async {
    final prefs = await SharedPreferences.getInstance();
    var changed = false;

    // Migration : ancienne clé unique → nouveau slot par service.
    final legacyId = prefs.getString(_legacyPrefKey);
    if (legacyId != null && legacyId.isNotEmpty) {
      for (final u in kSupportedUtilities) {
        if (u.id == legacyId) {
          if (u.service == ServiceType.electricity) {
            _overrideElec = u;
          } else {
            _overrideWater = u;
          }
          changed = true;
          break;
        }
      }
      await prefs.remove(_legacyPrefKey);
      await _persistOverrides(prefs);
    }

    // Chargement des slots actuels.
    final elecId = prefs.getString(_prefKeyElec);
    if (elecId != null && elecId.isNotEmpty) {
      for (final u in kSupportedUtilities) {
        if (u.id == elecId && u.service == ServiceType.electricity) {
          _overrideElec = u;
          changed = true;
          break;
        }
      }
    }
    final waterId = prefs.getString(_prefKeyWater);
    if (waterId != null && waterId.isNotEmpty) {
      for (final u in kSupportedUtilities) {
        if (u.id == waterId && u.service == ServiceType.water) {
          _overrideWater = u;
          changed = true;
          break;
        }
      }
    }

    if (changed) notifyListeners();
  }

  /// Écrit les deux slots d'override en SharedPreferences. Un slot null = clé
  /// supprimée (pas de marqueur résiduel).
  Future<void> _persistOverrides(SharedPreferences prefs) async {
    if (_overrideElec == null) {
      await prefs.remove(_prefKeyElec);
    } else {
      await prefs.setString(_prefKeyElec, _overrideElec!.id);
    }
    if (_overrideWater == null) {
      await prefs.remove(_prefKeyWater);
    } else {
      await prefs.setString(_prefKeyWater, _overrideWater!.id);
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

  Future<void> _loadServiceFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_serviceFilterKey);
    if (raw == null || raw.isEmpty) return;
    final parsed = ServiceType.values.where((s) => s.name == raw).firstOrNull;
    if (parsed != null) {
      _serviceFilter = parsed;
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

  /// Pose / retire le filtre service (null = Tout). Persisté.
  Future<void> setServiceFilter(ServiceType? value) async {
    if (value == _serviceFilter) return;
    _serviceFilter = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_serviceFilterKey);
    } else {
      await prefs.setString(_serviceFilterKey, value.name);
    }
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
  /// override dev (élec OU eau) → **GPS** → pays du profil → locale → défaut CM.
  /// L'override des deux services pointant sur le même pays (auto-coupling
  /// dans [setOverride]), le pays se lit indistinctement sur l'un ou l'autre.
  String get activeCountry {
    if (_overrideElec != null) return _overrideElec!.country;
    if (_overrideWater != null) return _overrideWater!.country;
    if (_detectedCountryIso != null) return _detectedCountryIso!;
    if (_homeCountryIso != null) return _homeCountryIso!;
    final loc = _localeCountry;
    if (loc != null && loc.isNotEmpty) return loc;
    return 'CM';
  }

  /// Fournisseur actif pour un service donné. L'override dev du service
  /// correspondant gagne ; sinon, résolution standard (pays actif × service).
  Utility? activeUtility(ServiceType service) {
    final override = overrideUtility(service);
    if (override != null) return override;
    return utilityForCountryAndService(activeCountry, service);
  }

  /// Compatibilité : équivalent de `activeUtility(ServiceType.electricity)`.
  /// Utilisé par les écrans existants qui parlent encore d'« électricité » par
  /// défaut (coupures planifiées Eneo, libellés de pays, etc.). À remplacer
  /// progressivement par l'appel paramétré.
  Utility? get activeProvider => activeUtility(ServiceType.electricity);

  /// Mis à jour par le profil (`homeLocation.country`). Re-résout si ça change.
  ///
  /// Cas particulier **session anonyme** : `countryName == null` (pas de profil)
  /// → `_homeCountryIso` est null, le pays actif retombe sur GPS → locale → `CM`.
  /// L'utilisateur peut toujours forcer via le sélecteur dev (override persisté).
  void setHomeCountry(String? countryName) {
    final iso = isoFromCountryName(countryName);
    if (iso == _homeCountryIso) return;
    _homeCountryIso = iso;
    notifyListeners();
  }

  /// Override dev pour [service] (`null` = auto). Persisté dans
  /// SharedPreferences.
  ///
  /// **Auto-coupling symétrique** : les deux slots restent synchronisés.
  /// - Poser un fournisseur (`utility != null`) **aligne automatiquement
  ///   l'autre service** sur le fournisseur du même pays, si présent dans
  ///   [kSupportedUtilities]. Sinon, l'autre slot reste inchangé.
  /// - Repasser un service en « Auto » (`utility == null`) **bascule aussi
  ///   l'autre service en Auto**. Le sélecteur des Paramètres se lit ainsi
  ///   comme un unique « pays/compagnie de test » à 2 facettes.
  Future<void> setOverride(ServiceType service, Utility? utility) async {
    if (utility == null) {
      _overrideElec = null;
      _overrideWater = null;
    } else {
      if (service == ServiceType.electricity) {
        _overrideElec = utility;
      } else {
        _overrideWater = utility;
      }
      final otherService =
          service == ServiceType.electricity
              ? ServiceType.water
              : ServiceType.electricity;
      final twin = utilityForCountryAndService(utility.country, otherService);
      if (twin != null) {
        if (otherService == ServiceType.electricity) {
          _overrideElec = twin;
        } else {
          _overrideWater = twin;
        }
      }
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _persistOverrides(prefs);
  }
}
