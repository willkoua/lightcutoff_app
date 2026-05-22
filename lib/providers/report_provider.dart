import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_constants.dart';
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
import '../utils/geohash.dart';

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

class ReportProvider extends ChangeNotifier with WidgetsBindingObserver {
  ReportProvider({
    ReportRepository? repository,
    LocationRepository? location,
    StorageRepository? storage,
    FirebaseAuth? auth,
  }) : _service = repository ?? ReportService(),
       _location = location ?? LocationService(),
       _storage = storage ?? StorageService(),
       _auth = auth ?? FirebaseAuth.instance {
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    _applyDefaultProximity();
  }

  /// Active le filtre « à proximité » par défaut, mais seulement si la
  /// localisation est déjà autorisée (sans déclencher de demande système au
  /// démarrage). Sinon, la liste reste non géolocalisée jusqu'à activation.
  Future<void> _applyDefaultProximity() async {
    try {
      if (await _location.checkAccess() != LocationAccess.granted) return;
      await setNearOnly(true);
      // Évite l'écran vide au démarrage : si rien à proximité (ou données pas
      // encore indexées en geohash), on revient à la liste complète. Le choix
      // manuel de l'utilisateur, lui, reste respecté même s'il est vide.
      if (_nearOnly && (_nearResults?.isEmpty ?? true)) {
        await setNearOnly(false);
      }
    } catch (_) {
      // Démarrage silencieux : on ignore toute erreur de localisation.
    }
  }

  final ReportRepository _service;
  final LocationRepository _location;
  final StorageRepository _storage;
  final FirebaseAuth _auth;
  late StreamSubscription<List<Report>> _sub;

  /// Taille courante de la fenêtre temps réel (grandit avec [loadMore]).
  int _limit = AppConstants.reportsPageSize;

  List<Report> _reports = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  bool _submitting = false;

  /// Écoute les coupures dans la limite courante. Re-souscrit à chaque
  /// [loadMore] avec une fenêtre élargie (on conserve le temps réel).
  void _subscribe() {
    _sub = _service
        .watchReports(limit: _limit)
        .listen(
          (data) {
            _reports = data;
            _hasMore = data.length >= _limit;
            _loading = false;
            _loadingMore = false;
            _error = null;
            notifyListeners();
          },
          onError: (Object e, StackTrace st) {
            CrashReporter.recordError(e, st, reason: 'watchReports');
            _error = 'Impossible de charger les coupures.';
            _loading = false;
            _loadingMore = false;
            notifyListeners();
          },
        );
  }

  /// Charge un lot supplémentaire (scroll infini). Sans effet si le dernier
  /// lot était incomplet (plus rien à charger) ou si un chargement est en cours.
  void loadMore() {
    if (_loading || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    _limit += AppConstants.reportsPageSize;
    notifyListeners();
    _sub.cancel();
    _subscribe();
  }

  // --- État des filtres / recherche ---
  // Filtres par défaut à l'ouverture : coupures « en cours », triées par
  // activité, et « à proximité » (activé au démarrage si la localisation est
  // déjà autorisée — voir _applyDefaultProximity).
  static const OutageStatus _defaultStatus = OutageStatus.ongoing;
  static const ReportSort _defaultSort = ReportSort.active;

  String _query = '';
  OutageStatus? _statusFilter = _defaultStatus;
  OutageType? _typeFilter;
  bool _onlyMine = false;
  bool _nearOnly = false;
  ReportSort _sort = _defaultSort;

  /// Résultats de la requête bornée par geohash (filtre « à proximité »).
  /// `null` quand le filtre est inactif.
  List<Report>? _nearResults;
  bool _nearLoading = false;

  /// Centre courant de la recherche de proximité (réutilisé par le
  /// rafraîchissement périodique) + son minuteur.
  GeoPosition? _nearCenter;
  Timer? _nearTimer;

  List<Report> get reports => _reports;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get submitting => _submitting;

  String get query => _query;
  OutageStatus? get statusFilter => _statusFilter;
  OutageType? get typeFilter => _typeFilter;
  bool get onlyMine => _onlyMine;
  bool get nearOnly => _nearOnly;
  bool get nearLoading => _nearLoading;
  ReportSort get sort => _sort;

  /// Vrai si l'utilisateur a modifié les filtres au-delà des valeurs par
  /// défaut (la proximité, qui est un mode par défaut, n'est pas comptée ici).
  bool get hasActiveFilters =>
      _query.isNotEmpty ||
      _statusFilter != _defaultStatus ||
      _typeFilter != null ||
      _onlyMine ||
      _sort != _defaultSort;

  /// Liste filtrée + triée selon l'état courant des filtres.
  ///
  /// En mode « à proximité », la base est le résultat de la requête bornée par
  /// geohash (déjà filtrée par distance) ; sinon, le flux temps réel paginé.
  List<Report> get filteredReports {
    final q = _query.trim().toLowerCase();
    final base = _nearOnly ? (_nearResults ?? const <Report>[]) : _reports;
    final list =
        base.where((r) {
          if (_statusFilter != null && r.status != _statusFilter) return false;
          if (_typeFilter != null && r.type != _typeFilter) return false;
          if (_onlyMine && r.userId != _uid) return false;
          if (q.isNotEmpty) {
            final haystack =
                '${r.location.label} ${r.description ?? ''}'.toLowerCase();
            if (!haystack.contains(q)) return false;
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

  void setTypeFilter(OutageType? type) {
    _typeFilter = type;
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
      _nearTimer?.cancel();
      _nearOnly = false;
      _nearResults = null;
      _nearCenter = null;
      notifyListeners();
      return null;
    }
    try {
      final loc = await _location.getCurrentLocation();
      _nearCenter = loc.position;
      _nearOnly = true;
      _nearLoading = true;
      notifyListeners();
      // Requête bornée par geohash (centre + voisines), affinée par distance.
      _nearResults = await _fetchNear();
      _nearLoading = false;
      notifyListeners();
      _startNearAutoRefresh();
      return null;
    } on LocationException catch (e) {
      _resetNear();
      return e.message;
    } catch (_) {
      _resetNear();
      return 'Localisation impossible.';
    }
  }

  void _resetNear() {
    _nearTimer?.cancel();
    _nearOnly = false;
    _nearLoading = false;
    _nearCenter = null;
    notifyListeners();
  }

  Future<List<Report>> _fetchNear() => _service.reportsWithinRadius(
    lat: _nearCenter!.lat,
    lng: _nearCenter!.lng,
    radiusMeters: AppConstants.nearbyFilterRadiusMeters,
  );

  /// Démarre le rafraîchissement périodique des résultats de proximité
  /// (la requête n'étant pas temps réel).
  void _startNearAutoRefresh() {
    _nearTimer?.cancel();
    _nearTimer = Timer.periodic(
      AppConstants.nearRefreshInterval,
      (_) => _refreshNear(),
    );
  }

  /// Recharge silencieusement les coupures à proximité (sans spinner).
  Future<void> _refreshNear() async {
    if (!_nearOnly || _nearCenter == null) return;
    try {
      _nearResults = await _fetchNear();
      notifyListeners();
    } catch (_) {
      // On conserve les résultats précédents en cas d'échec ponctuel.
    }
  }

  /// Rafraîchissement manuel (pull-to-refresh). En mode proximité, relance la
  /// requête ; sinon le flux principal est déjà temps réel (rien à recharger).
  Future<void> refresh() async {
    if (_nearOnly && _nearCenter != null) {
      await _refreshNear();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Met le rafraîchissement périodique en pause hors-écran (économie batterie
  /// et lectures), et le relance — avec un rafraîchissement immédiat — au retour.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_nearOnly && _nearCenter != null) {
        _refreshNear();
        _startNearAutoRefresh();
      }
    } else {
      _nearTimer?.cancel();
    }
  }

  /// Réinitialise aux filtres par défaut (en cours · toutes · activité) et
  /// réactive la proximité si la localisation est disponible.
  void clearFilters() {
    _query = '';
    _statusFilter = _defaultStatus;
    _typeFilter = null;
    _onlyMine = false;
    _sort = _defaultSort;
    notifyListeners();
    if (!_nearOnly) _applyDefaultProximity();
  }

  String? get _uid => _auth.currentUser?.uid;
  String? get currentUid => _uid;

  bool isAuthor(Report report) => report.userId == _uid;

  /// Retourne la coupure correspondante dans la liste courante (flux temps réel
  /// ou résultats de proximité), sinon null.
  Report? reportById(String id) {
    for (final r in _reports) {
      if (r.id == id) return r;
    }
    for (final r in _nearResults ?? const <Report>[]) {
      if (r.id == id) return r;
    }
    return null;
  }

  Stream<List<Confirmation>> watchConfirmations(String reportId) =>
      _service.watchConfirmations(reportId);

  /// Crée un signalement à la position courante. Retourne null si OK,
  /// sinon un message d'erreur.
  Future<String?> submitReport({
    String? description,
    String? authorUsername,
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
        // Tout signalement citoyen est une coupure imprévue.
        type: OutageType.unplanned,
        position: loc.position,
        location: loc.area,
        description:
            (description?.trim().isEmpty ?? true) ? null : description!.trim(),
        authorUsername: authorUsername,
        geohash: encodeGeohash(loc.position.lat, loc.position.lng),
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

  static const Distance _distance = Distance();

  /// Coupure « en cours » la plus proche de [pos] dans le rayon, sinon null.
  Report? findNearbyOngoing(
    GeoPosition pos, {
    double radiusMeters = AppConstants.duplicateRadiusMeters,
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
    String? description,
    String? mediaUrl,
    String? authorUsername,
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
        // Tout signalement citoyen est une coupure imprévue.
        type: OutageType.unplanned,
        position: draft.position,
        location: draft.area,
        description:
            (description?.trim().isEmpty ?? true) ? null : description!.trim(),
        mediaUrl: mediaUrl,
        authorUsername: authorUsername,
        geohash: encodeGeohash(draft.position.lat, draft.position.lng),
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
      // En mode proximité (requête ponctuelle), on resynchronise tout de suite.
      if (_nearOnly) await _refreshNear();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resolve(String reportId) async {
    try {
      await _service.resolveReport(reportId);
      // En mode proximité (requête ponctuelle), on resynchronise tout de suite.
      if (_nearOnly) await _refreshNear();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    _nearTimer?.cancel();
    super.dispose();
  }
}
