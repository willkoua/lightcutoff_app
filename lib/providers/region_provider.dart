import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/utilities.dart';
import '../models/enums.dart';
import '../repositories/location_repository.dart';
import '../services/ip_country_service.dart';
import '../services/location_service.dart';
import '../services/utility_service.dart';

/// Détermine le **fournisseur de service public actif** (pays + compagnie) pour
/// aller chercher les coupures planifiées et taguer les signalements.
///
/// Priorité de résolution du pays :
///   1. **override dev** (persisté, dev/staging uniquement)
///   2. **choix utilisateur** (sélecteur Paramètres, dev/staging uniquement —
///      en prod le pays est TOUJOURS détecté automatiquement)
///   3. **GPS** (où se trouve l'utilisateur), avec **repli IP**
///      (`api.country.is`) si la localisation est refusée/indisponible
///   4. **`homeLocation.country`** du profil (renseigné via le proxy AuthProvider)
///   5. **pays de la locale du téléphone** (sans permission)
///   6. défaut **`CM`**
///
/// Multi-service (introduit avec le pivot 2026-06-24) : pour un même pays, on
/// expose un fournisseur **par service** ([activeUtility]). L'override dev,
/// quand posé, est lié à un service précis — il ne « remplace » donc que la
/// résolution de ce service-là.
class RegionProvider extends ChangeNotifier {
  RegionProvider({
    LocationRepository? location,
    Future<String?> Function()? ipCountry,
    Future<RemoteUtilities?> Function()? remoteUtilities,
  }) : _location = location ?? LocationService(),
       _ipCountry = ipCountry ?? countryFromIp,
       _remoteUtilities = remoteUtilities ?? fetchRemoteUtilities {
    _refreshUtilities();
    _loadOverride();
    _loadUserCountry();
    _loadWorldwide();
    _loadServiceFilter();
    _detectCountry();
  }

  /// Rafraîchit le catalogue des compagnies depuis Firestore (`utilities`) —
  /// source de vérité depuis le 2026-08-13, l'embarqué n'étant qu'un filet.
  /// Best-effort : en cas d'échec (hors-ligne, premier démarrage sans réseau,
  /// environnement de test sans Firebase), le registre embarqué reste actif.
  Future<void> _refreshUtilities() async {
    final remote = await _remoteUtilities();
    if (remote == null) return;
    applyRemoteUtilities(remote.upserts, disabledIds: remote.disabledIds);
    // Les pickers, `activeUtility` et les libellés pays dépendent du registre.
    notifyListeners();
  }

  // Nouvelles clés (pivot étape 3 — 1 override par service).
  static const _prefKeyElec = 'provider_override_electricity_id';
  static const _prefKeyWater = 'provider_override_water_id';
  // Clé héritée (avant la séparation par service). Migrée puis supprimée au
  // 1ʳᵉ chargement — voir `_loadOverride`.
  static const _legacyPrefKey = 'provider_override_id';
  static const _worldwideKey = 'admin_worldwide';
  static const _serviceFilterKey = 'service_filter';
  // Pays choisi **explicitement** par l'utilisateur (sélecteur Paramètres,
  // dev/staging UNIQUEMENT depuis le 2026-07-28 — en prod le pays est détecté
  // automatiquement, GPS puis IP). Prioritaire sur la détection auto quand
  // il est actif — voir `activeCountry`.
  static const _userCountryKey = 'user_country_iso';

  final LocationRepository _location;
  final Future<String?> Function() _ipCountry;
  final Future<RemoteUtilities?> Function() _remoteUtilities;
  bool _ipLookupDone = false; // repli IP tenté (une fois par session)

  /// Override dev par service. `null` = résolution standard (GPS / profil /
  /// locale / défaut CM). Le picker des Paramètres expose UN champ par
  /// service ; sélectionner un fournisseur d'un pays X **aligne
  /// automatiquement** l'autre service sur le fournisseur du même pays
  /// (si présent dans `kSupportedUtilities`).
  Utility? _overrideElec;
  Utility? _overrideWater;

  String? _detectedCountryIso; // pays GPS (où se trouve l'utilisateur)
  String? _homeCountryIso; // dérivé de homeLocation du profil
  String? _userCountryIso; // pays choisi explicitement par l'utilisateur
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
      for (final u in supportedUtilities) {
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
      for (final u in supportedUtilities) {
        if (u.id == elecId && u.service == ServiceType.electricity) {
          _overrideElec = u;
          changed = true;
          break;
        }
      }
    }
    final waterId = prefs.getString(_prefKeyWater);
    if (waterId != null && waterId.isNotEmpty) {
      for (final u in supportedUtilities) {
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

  /// Pays choisi explicitement par l'utilisateur (ISO), ou `null` si en mode
  /// automatique (détection GPS / profil / locale).
  String? get userCountry => _userCountryIso;

  Future<void> _loadUserCountry() async {
    // En prod, le choix manuel n'existe plus : on n'applique pas non plus une
    // éventuelle valeur persistée (résidu d'un ancien build / de staging) —
    // c'est elle qui cachait ses propres signalements à l'utilisateur
    // (incident 2026-07-28). Gate sur `isProd` (pas `showDevTools`) : le mode
    // capture (SCREENSHOT_MODE) masque le sélecteur mais doit HONORER le pays
    // choisi, sinon impossible de capturer les données seedées CM.
    if (AppConfig.isProd) return;
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_userCountryKey);
    if (iso != null && iso.isNotEmpty && iso != _userCountryIso) {
      _userCountryIso = iso.toUpperCase();
      notifyListeners();
    }
  }

  /// Définit (ou efface, `null` = automatique) le pays choisi par l'utilisateur.
  /// Persisté. Prioritaire sur la détection auto dans [activeCountry].
  Future<void> setUserCountry(String? iso) async {
    final normalized = (iso == null || iso.isEmpty) ? null : iso.toUpperCase();
    if (normalized == _userCountryIso) return;
    _userCountryIso = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.remove(_userCountryKey);
    } else {
      await prefs.setString(_userCountryKey, normalized);
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

  /// Détecte le pays où se trouve l'utilisateur : **GPS d'abord** (si la
  /// localisation est déjà autorisée — best-effort, sans déclencher de
  /// demande), sinon **repli IP** (`api.country.is`, une tentative par
  /// session). Le GPS prime toujours : l'IP peut être faussée par un VPN.
  Future<void> _detectCountry() async {
    try {
      if (await _location.checkAccess() == LocationAccess.granted) {
        final loc = await _location.getCurrentLocation();
        final iso = loc.area.countryCode.toUpperCase();
        if (iso.isNotEmpty && iso != _detectedCountryIso) {
          _detectedCountryIso = iso;
          notifyListeners();
        }
        if (_detectedCountryIso != null) return;
      }
    } catch (_) {
      // best-effort : on tente le repli IP ci-dessous.
    }
    if (_detectedCountryIso != null || _ipLookupDone) return;
    _ipLookupDone = true;
    final iso = await _ipCountry();
    if (iso != null && iso != _detectedCountryIso) {
      _detectedCountryIso = iso;
      notifyListeners();
    }
  }

  /// Pays détecté automatiquement (GPS, sinon IP), ou `null` si aucune
  /// détection n'a abouti. Sert au formulaire de signalement pour avertir
  /// d'un décalage avec le pays sélectionné (dev/staging).
  String? get detectedCountry => _detectedCountryIso;

  /// Pays actif (ISO), selon la priorité :
  /// override dev (élec OU eau) → **choix utilisateur** (dev/staging
  /// uniquement) → détection auto (GPS puis IP) → pays du profil → locale →
  /// défaut CM. En prod, seuls la détection et les replis s'appliquent.
  String get activeCountry {
    if (_overrideElec != null) return _overrideElec!.country;
    if (_overrideWater != null) return _overrideWater!.country;
    if (!AppConfig.isProd && _userCountryIso != null) {
      return _userCountryIso!;
    }
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
  /// défaut (coupures planifiées SOCADEL, libellés de pays, etc.). À remplacer
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
