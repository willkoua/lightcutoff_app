import 'package:flutter/foundation.dart';

import '../config/app_constants.dart';
import '../repositories/location_repository.dart';
import '../repositories/report_repository.dart';
import '../services/location_service.dart';
import '../services/report_service.dart';
import '../utils/outage_stats.dart';

/// État de chargement des statistiques perso.
enum StatsStatus { loading, ready, error }

/// Alimente l'écran « Statistiques » : agrège **mes coupures** (par auteur) et
/// **ma zone** (rayon autour de la position courante). Lecture unique au
/// chargement ; recalcul à la demande via [load].
///
/// Confidentialité : ne manipule que des agrégats ([OutageStats]) — aucune
/// donnée individuelle d'un autre utilisateur n'est exposée.
class StatsProvider extends ChangeNotifier {
  StatsProvider({ReportRepository? reports, LocationRepository? location})
    : _reports = reports ?? ReportService(),
      _location = location ?? LocationService();

  final ReportRepository _reports;
  final LocationRepository _location;

  StatsStatus _status = StatsStatus.loading;
  StatsStatus get status => _status;

  OutageStats? _mine;

  /// Stats des coupures créées par l'utilisateur.
  OutageStats? get mine => _mine;

  OutageStats? _zone;

  /// Stats agrégées de la zone autour de l'utilisateur. `null` si la position
  /// n'a pas pu être obtenue (cf. [zoneUnavailable]).
  OutageStats? get zone => _zone;

  bool _zoneUnavailable = false;

  /// `true` si « ma zone » n'a pas pu être calculée (localisation indisponible
  /// ou refusée) → l'UI affiche un message dédié plutôt qu'un écran vide.
  bool get zoneUnavailable => _zoneUnavailable;

  /// Rayon de « ma zone » = rayon d'alerte des coupures (cohérence : la zone
  /// pour laquelle on serait notifié).
  static const double zoneRadiusMeters = AppConstants.notifyRadiusMeters;

  /// Charge les deux jeux de stats pour [uid]. Idempotent ; rejouable en
  /// pull-to-refresh.
  Future<void> load(String uid) async {
    _status = StatsStatus.loading;
    _zoneUnavailable = false;
    notifyListeners();
    try {
      _mine = computeOutageStats(await _reports.reportsByAuthor(uid));
      _zone = await _loadZone();
      _status = StatsStatus.ready;
    } catch (_) {
      _status = StatsStatus.error;
    }
    notifyListeners();
  }

  /// « Ma zone » nécessite la position courante. Si la localisation est
  /// indisponible/refusée, on dégrade proprement (zone nulle + drapeau) sans
  /// faire échouer tout l'écran.
  Future<OutageStats?> _loadZone() async {
    try {
      if (await _location.checkAccess() != LocationAccess.granted) {
        _zoneUnavailable = true;
        return null;
      }
      final loc = await _location.getCurrentLocation();
      final nearby = await _reports.reportsWithinRadius(
        lat: loc.position.lat,
        lng: loc.position.lng,
        radiusMeters: zoneRadiusMeters,
      );
      return computeOutageStats(nearby);
    } catch (_) {
      _zoneUnavailable = true;
      return null;
    }
  }
}
