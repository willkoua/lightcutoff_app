import 'package:flutter/foundation.dart';

import '../config/app_constants.dart';
import '../models/enums.dart';
import '../models/report.dart';
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

  /// Reports bruts (toutes services confondus). Le calcul des [OutageStats]
  /// se fait à la volée via [mineFor]/[zoneFor] pour permettre le filtrage
  /// par service sans rechargement réseau.
  List<Report> _mineReports = const [];
  List<Report> _zoneReports = const [];

  /// Stats des coupures créées par l'utilisateur (tous services).
  OutageStats? get mine =>
      _status == StatsStatus.ready ? computeOutageStats(_mineReports) : null;

  /// Stats agrégées de la zone autour de l'utilisateur, tous services
  /// confondus. `null` si la position n'a pas pu être obtenue (cf.
  /// [zoneUnavailable]).
  OutageStats? get zone =>
      _status == StatsStatus.ready && !_zoneUnavailable
          ? computeOutageStats(_zoneReports)
          : null;

  /// Stats des coupures créées par l'utilisateur, filtrées par [service]
  /// (`null` = tous services confondus = [mine]).
  OutageStats? mineFor(ServiceType? service) {
    if (_status != StatsStatus.ready) return null;
    if (service == null) return computeOutageStats(_mineReports);
    return computeOutageStats(
      _mineReports.where((r) => r.serviceType == service).toList(),
    );
  }

  /// Stats de zone filtrées par [service] (`null` = tous services).
  OutageStats? zoneFor(ServiceType? service) {
    if (_status != StatsStatus.ready || _zoneUnavailable) return null;
    if (service == null) return computeOutageStats(_zoneReports);
    return computeOutageStats(
      _zoneReports.where((r) => r.serviceType == service).toList(),
    );
  }

  bool _zoneUnavailable = false;

  /// `true` si « ma zone » n'a pas pu être calculée (localisation indisponible
  /// ou refusée) → l'UI affiche un message dédié plutôt qu'un écran vide.
  bool get zoneUnavailable => _zoneUnavailable;

  /// Rayon de « ma zone » = rayon d'alerte des coupures (cohérence : la zone
  /// pour laquelle on serait notifié).
  static const double zoneRadiusMeters = AppConstants.notifyRadiusMeters;

  /// Charge les deux jeux de reports pour [uid]. Idempotent ; rejouable en
  /// pull-to-refresh. Le filtrage par service est appliqué à la volée par
  /// [mineFor]/[zoneFor] — pas besoin de recharger quand le filtre change.
  Future<void> load(String uid) async {
    _status = StatsStatus.loading;
    _zoneUnavailable = false;
    notifyListeners();
    try {
      _mineReports = await _reports.reportsByAuthor(uid);
      _zoneReports = await _loadZoneReports();
      _status = StatsStatus.ready;
    } catch (_) {
      _status = StatsStatus.error;
    }
    notifyListeners();
  }

  /// « Ma zone » nécessite la position courante. Si la localisation est
  /// indisponible/refusée, on dégrade proprement (zone nulle + drapeau) sans
  /// faire échouer tout l'écran.
  Future<List<Report>> _loadZoneReports() async {
    try {
      if (await _location.checkAccess() != LocationAccess.granted) {
        _zoneUnavailable = true;
        return const [];
      }
      final loc = await _location.getCurrentLocation();
      return await _reports.reportsWithinRadius(
        lat: loc.position.lat,
        lng: loc.position.lng,
        radiusMeters: zoneRadiusMeters,
      );
    } catch (_) {
      _zoneUnavailable = true;
      return const [];
    }
  }
}
