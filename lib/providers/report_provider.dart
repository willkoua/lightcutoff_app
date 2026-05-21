import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/report.dart';
import '../services/location_service.dart';
import '../services/report_service.dart';

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
