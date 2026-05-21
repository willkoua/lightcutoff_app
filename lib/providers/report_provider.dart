import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/enums.dart';
import '../models/geo.dart';
import '../models/report.dart';
import '../services/location_service.dart';
import '../services/report_service.dart';

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

class ReportProvider extends ChangeNotifier {
  ReportProvider({
    ReportService? service,
    LocationService? location,
    FirebaseAuth? auth,
  })  : _service = service ?? ReportService(),
        _location = location ?? LocationService(),
        _auth = auth ?? FirebaseAuth.instance {
    _sub = _service.watchReports().listen(
      (data) {
        _reports = data;
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (_) {
        _error = 'Impossible de charger les coupures.';
        _loading = false;
        notifyListeners();
      },
    );
  }

  final ReportService _service;
  final LocationService _location;
  final FirebaseAuth _auth;
  late final StreamSubscription<List<Report>> _sub;

  List<Report> _reports = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  List<Report> get reports => _reports;
  bool get loading => _loading;
  String? get error => _error;
  bool get submitting => _submitting;

  String? get _uid => _auth.currentUser?.uid;

  bool isAuthor(Report report) => report.userId == _uid;

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
        description: (description?.trim().isEmpty ?? true)
            ? null
            : description!.trim(),
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

  /// Crée le signalement à partir d'une localisation déjà résolue.
  Future<String?> createFromDraft(
    ReportDraft draft, {
    required OutageCause cause,
    String? description,
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
        description: (description?.trim().isEmpty ?? true)
            ? null
            : description!.trim(),
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
