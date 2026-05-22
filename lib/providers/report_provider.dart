import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/confirmation.dart';
import '../models/enums.dart';
import '../models/geo.dart';
import '../models/report.dart';
import '../repositories/location_repository.dart';
import '../repositories/report_repository.dart';
import '../repositories/storage_repository.dart';
import '../services/location_service.dart';
import '../services/report_service.dart';
import '../services/storage_service.dart';
import '../utils/crash_reporter.dart';

/// Localisation résolue, prête à devenir un signalement.
class ReportDraft {
  final GeoPosition position;
  final GeoArea area;
  const ReportDraft({required this.position, required this.area});
}

/// Résultat de la préparation d'un signalement.
class PrepareOutcome {
  final String? error;
  final ReportDraft? draft;

  /// Coupure « en cours » la plus proche dans le rayon, sinon null.
  final Report? nearby;

  const PrepareOutcome({this.error, this.draft, this.nearby});
}

/// Critère de tri de la liste des coupures.
enum ReportSort { recent, active, confirmed }

class ReportProvider extends ChangeNotifier {
  ReportProvider({
    ReportRepository? repository,
    LocationRepository? location,
    StorageRepository? storage,
    FirebaseAuth? auth,
  }) : _service = repository ?? ReportService(),
       _location = location ?? LocationService(),
       _storage = storage ?? StorageService(),
       _auth = auth ?? FirebaseAuth.instance {
    _sub = _service.watchReports().listen(
      (data) {
        _reports = data;
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        CrashReporter.recordError(e, st, reason: 'watchReports');
        _error = 'Impossible de charger les coupures.';
        _loading = false;
        notifyListeners();
      },
    );
  }

  final ReportRepository _service;
  final LocationRepository _location;
  final StorageRepository _storage;
  final FirebaseAuth _auth;
  late final StreamSubscription<List<Report>> _sub;

  List<Report> _reports = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  // --- État des filtres / recherche ---
  String _query = '';
  OutageStatus? _statusFilter;
  OutageCause? _causeFilter;
  bool _onlyMine = false;
  bool _nearOnly = false;
  GeoPosition? _nearPosition;
  ReportSort _sort = ReportSort.recent;

  /// Rayon (m) du filtre « à proximité ».
  static const double nearFilterRadiusMeters = 5000;

  List<Report> get reports => _reports;
  bool get loading => _loading;
  String? get error => _error;
  bool get submitting => _submitting;

  String get query => _query;
  OutageStatus? get statusFilter => _statusFilter;
  OutageCause? get causeFilter => _causeFilter;
  bool get onlyMine => _onlyMine;
  bool get nearOnly => _nearOnly;
  ReportSort get sort => _sort;

  bool get hasActiveFilters =>
      _query.isNotEmpty ||
      _statusFilter != null ||
      _causeFilter != null ||
      _onlyMine ||
      _nearOnly;

  /// Liste filtrée + triée selon l'état courant des filtres.
  List<Report> get filteredReports {
    final q = _query.trim().toLowerCase();
    final list =
        _reports.where((r) {
          if (_statusFilter != null && r.status != _statusFilter) return false;
          if (_causeFilter != null && r.cause != _causeFilter) return false;
          if (_onlyMine && r.userId != _uid) return false;
          if (q.isNotEmpty) {
            final haystack =
                '${r.location.label} ${r.description ?? ''}'.toLowerCase();
            if (!haystack.contains(q)) return false;
          }
          if (_nearOnly && _nearPosition != null) {
            final d = _distance.as(
              LengthUnit.Meter,
              LatLng(_nearPosition!.lat, _nearPosition!.lng),
              LatLng(r.position.lat, r.position.lng),
            );
            if (d > nearFilterRadiusMeters) return false;
          }
          return true;
        }).toList();

    int byDate(DateTime? a, DateTime? b) =>
        (b ?? DateTime(0)).compareTo(a ?? DateTime(0));
    switch (_sort) {
      case ReportSort.recent:
        list.sort((a, b) => byDate(a.reportedAt, b.reportedAt));
      case ReportSort.active:
        list.sort((a, b) => byDate(a.updatedAt, b.updatedAt));
      case ReportSort.confirmed:
        list.sort((a, b) => b.confirmationCount.compareTo(a.confirmationCount));
    }
    return list;
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  /// Bascule un statut (re-tap = désactive le filtre).
  void toggleStatusFilter(OutageStatus status) {
    _statusFilter = _statusFilter == status ? null : status;
    notifyListeners();
  }

  void setCauseFilter(OutageCause? cause) {
    _causeFilter = cause;
    notifyListeners();
  }

  void toggleOnlyMine() {
    _onlyMine = !_onlyMine;
    notifyListeners();
  }

  void setSort(ReportSort value) {
    _sort = value;
    notifyListeners();
  }

  /// Active/désactive le filtre de proximité. Retourne un message d'erreur
  /// si la position n'a pas pu être obtenue.
  Future<String?> setNearOnly(bool value) async {
    if (!value) {
      _nearOnly = false;
      _nearPosition = null;
      notifyListeners();
      return null;
    }
    try {
      final loc = await _location.getCurrentLocation();
      _nearPosition = loc.position;
      _nearOnly = true;
      notifyListeners();
      return null;
    } on LocationException catch (e) {
      return e.message;
    } catch (_) {
      return 'Localisation impossible.';
    }
  }

  void clearFilters() {
    _query = '';
    _statusFilter = null;
    _causeFilter = null;
    _onlyMine = false;
    _nearOnly = false;
    _nearPosition = null;
    _sort = ReportSort.recent;
    notifyListeners();
  }

  String? get _uid => _auth.currentUser?.uid;
  String? get currentUid => _uid;

  bool isAuthor(Report report) => report.userId == _uid;

  /// Retourne la coupure correspondante dans la liste courante, sinon null.
  Report? reportById(String id) {
    for (final r in _reports) {
      if (r.id == id) return r;
    }
    return null;
  }

  Stream<List<Confirmation>> watchConfirmations(String reportId) =>
      _service.watchConfirmations(reportId);

  /// Crée un signalement à la position courante. Retourne null si OK,
  /// sinon un message d'erreur.
  Future<String?> submitReport({
    required OutageCause cause,
    String? description,
  }) async {
    final uid = _uid;
    if (uid == null) return 'Vous devez être connecté.';

    _submitting = true;
    notifyListeners();
    try {
      final loc = await _location.getCurrentLocation();
      final report = Report(
        id: '',
        userId: uid,
        status: OutageStatus.ongoing,
        cause: cause,
        position: loc.position,
        location: loc.area,
        description:
            (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      );
      await _service.createReport(report);
      return null;
    } on LocationException catch (e) {
      return e.message;
    } catch (_) {
      return 'Échec du signalement. Réessayez.';
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Rayon (m) en-deçà duquel deux coupures sont considérées identiques.
  static const double duplicateRadiusMeters = 500;

  static const Distance _distance = Distance();

  /// Coupure « en cours » la plus proche de [pos] dans le rayon, sinon null.
  Report? findNearbyOngoing(
    GeoPosition pos, {
    double radiusMeters = duplicateRadiusMeters,
  }) {
    final origin = LatLng(pos.lat, pos.lng);
    Report? best;
    double bestDistance = double.infinity;
    for (final report in _reports) {
      if (report.status != OutageStatus.ongoing) continue;
      final d = _distance.as(
        LengthUnit.Meter,
        origin,
        LatLng(report.position.lat, report.position.lng),
      );
      if (d <= radiusMeters && d < bestDistance) {
        best = report;
        bestDistance = d;
      }
    }
    return best;
  }

  /// Position GPS courante (ou null en cas d'échec/refus). Pour la carte.
  Future<GeoPosition?> myPosition() async {
    try {
      final loc = await _location.getCurrentLocation();
      return loc.position;
    } catch (_) {
      return null;
    }
  }

  /// État d'accès à la localisation (sans déclencher la demande système).
  Future<LocationAccess> checkLocationAccess() => _location.checkAccess();

  /// Ouvre les réglages système de l'app.
  Future<void> openLocationSettings() => _location.openSettings();

  /// Récupère la position et cherche un éventuel doublon proche.
  Future<PrepareOutcome> prepareReport() async {
    if (_uid == null) {
      return const PrepareOutcome(error: 'Vous devez être connecté.');
    }
    _submitting = true;
    notifyListeners();
    try {
      final loc = await _location.getCurrentLocation();
      final draft = ReportDraft(position: loc.position, area: loc.area);
      return PrepareOutcome(
        draft: draft,
        nearby: findNearbyOngoing(loc.position),
      );
    } on LocationException catch (e) {
      return PrepareOutcome(error: e.message);
    } catch (_) {
      return const PrepareOutcome(error: 'Localisation impossible. Réessayez.');
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Upload un média (octets) pour la description courante. Renvoie l'URL,
  /// ou null en cas d'échec.
  Future<String?> uploadDescriptionMedia(
    Uint8List bytes, {
    String contentType = 'image/gif',
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      return await _storage.uploadReportMedia(
        uid: uid,
        bytes: bytes,
        contentType: contentType,
      );
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'uploadDescriptionMedia');
      return null;
    }
  }

  /// Crée le signalement à partir d'une localisation déjà résolue.
  Future<String?> createFromDraft(
    ReportDraft draft, {
    required OutageCause cause,
    String? description,
    String? mediaUrl,
  }) async {
    final uid = _uid;
    if (uid == null) return 'Vous devez être connecté.';
    _submitting = true;
    notifyListeners();
    try {
      final report = Report(
        id: '',
        userId: uid,
        status: OutageStatus.ongoing,
        cause: cause,
        position: draft.position,
        location: draft.area,
        description:
            (description?.trim().isEmpty ?? true) ? null : description!.trim(),
        mediaUrl: mediaUrl,
      );
      await _service.createReport(report);
      return null;
    } catch (_) {
      return 'Échec du signalement. Réessayez.';
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<bool> confirm(String reportId) async {
    final uid = _uid;
    if (uid == null) return false;
    // Garde : on ne confirme pas sa propre coupure.
    if (reportById(reportId)?.userId == uid) return false;
    try {
      await _service.confirmReport(reportId, uid);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resolve(String reportId) async {
    try {
      await _service.resolveReport(reportId);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
