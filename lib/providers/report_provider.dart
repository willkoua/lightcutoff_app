import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';
import '../config/utilities.dart';
import '../models/app_error.dart';
import '../models/confirmation.dart';
import '../models/enums.dart';
import '../models/geo.dart';
import '../models/report.dart';
import '../models/restoration.dart';
import '../repositories/location_repository.dart';
import '../repositories/report_repository.dart';
import '../repositories/storage_repository.dart';
import '../services/analytics_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../services/storage_service.dart';
import '../utils/anonymous_activity.dart';
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
  final AppError? error;
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
    _loadDismissedPrompts();
  }

  /// Active le filtre « à proximité » **par défaut**, dès que la localisation
  /// est autorisée (sans déclencher de demande système au démarrage). Le filtre
  /// reste actif même s'il n'y a aucune coupure proche (état vide explicite) ;
  /// l'utilisateur peut l'enlever via le panneau de filtres. Sans permission, la
  /// liste reste non géolocalisée jusqu'à activation manuelle.
  Future<void> _applyDefaultProximity() async {
    try {
      if (await _location.checkAccess() != LocationAccess.granted) return;
      await setNearOnly(true);
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
  AppError? _error;
  bool _submitting = false;

  /// IDs des reports que l'utilisateur courant a déjà confirmés / dont il a déjà
  /// signalé le retour du courant. Alimentés optimistiquement à l'action et
  /// hydratés à l'ouverture du détail ([hydrateMyVotes]) pour survivre à un
  /// redémarrage. Permettent d'afficher clairement « tu as déjà voté ».
  final Set<String> _myConfirmedIds = {};
  final Set<String> _myRestoredIds = {};

  bool iConfirmed(String reportId) => _myConfirmedIds.contains(reportId);
  bool iRestored(String reportId) => _myRestoredIds.contains(reportId);

  // --- Prompt d'ouverture « Chez toi aussi ? » ---
  // Reports pour lesquels l'utilisateur a déjà répondu (Oui/Non) ou glissé le
  // prompt. Persisté (SharedPreferences) pour ne JAMAIS re-solliciter sur le
  // même signalement, même après redémarrage.
  static const String _dismissedPromptsKey = 'prompt_dismissed_report_ids';
  final Set<String> _dismissedPromptIds = {};
  bool _dismissedPromptsLoaded = false;
  bool _disposed = false;

  Future<void> _loadDismissedPrompts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedPromptIds.addAll(
        prefs.getStringList(_dismissedPromptsKey) ?? const [],
      );
    } catch (_) {
      // Best-effort : sans persistance on retombe sur l'état mémoire.
    } finally {
      _dismissedPromptsLoaded = true;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _persistDismissedPrompt(String reportId) async {
    _dismissedPromptIds.add(reportId);
    if (!_disposed) notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _dismissedPromptsKey,
        _dismissedPromptIds.toList(),
      );
    } catch (_) {
      // Best-effort.
    }
  }

  /// Écarte le prompt pour ce report sans répondre (« passer »).
  void dismissPrompt(String reportId) {
    _persistDismissedPrompt(reportId);
    AnalyticsService.instance.logPromptDismissed();
  }

  /// Candidat au prompt d'ouverture « Chez toi aussi ? » : la coupure **en
  /// cours** la plus proche à moins de [AppConstants.promptRadiusMeters],
  /// dont l'utilisateur n'est pas l'auteur, sur laquelle il n'a pas encore
  /// voté et qu'il n'a pas déjà écartée. `null` si rien à demander (pas de
  /// position connue, rien de proche, ou déjà sollicité).
  Report? get promptCandidate {
    if (!_dismissedPromptsLoaded) return null;
    final center = _nearCenter;
    final results = _nearResults;
    if (center == null || results == null) return null;
    const distance = Distance();
    Report? best;
    double bestMeters = AppConstants.promptRadiusMeters;
    for (final r in results) {
      if (r.status != OutageStatus.ongoing) continue;
      if (r.userId == _uid) continue;
      if (_dismissedPromptIds.contains(r.id)) continue;
      if (_myConfirmedIds.contains(r.id) || _myRestoredIds.contains(r.id)) {
        continue;
      }
      if (_countryFilter != null && r.location.countryCode != _countryFilter) {
        continue;
      }
      final d = distance.as(
        LengthUnit.Meter,
        LatLng(center.lat, center.lng),
        LatLng(r.position.lat, r.position.lng),
      );
      if (d <= bestMeters) {
        bestMeters = d;
        best = r;
      }
    }
    return best;
  }

  /// Vérifie côté serveur si l'utilisateur a déjà confirmé / signalé le retour
  /// pour [reportId] et met à jour l'état local. Idempotent ; sans effet hors
  /// connexion ou en cas d'erreur (l'état optimiste reste la source).
  Future<void> hydrateMyVotes(String reportId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final results = await Future.wait([
        _service.hasConfirmed(reportId, uid),
        _service.hasRestored(reportId, uid),
      ]);
      var changed = false;
      if (results[0] && _myConfirmedIds.add(reportId)) changed = true;
      if (results[1] && _myRestoredIds.add(reportId)) changed = true;
      if (changed) notifyListeners();
    } catch (_) {
      // Lecture best-effort : on garde l'état optimiste existant.
    }
  }

  /// Écoute les coupures dans la limite courante. Re-souscrit à chaque
  /// [loadMore] avec une fenêtre élargie (on conserve le temps réel).
  void _subscribe() {
    _sub = _service
        .watchReports(limit: _limit, countryCode: _countryFilter)
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
            _error = AppError.reportsLoadFailed;
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
  bool _onlyMine = false;
  bool _nearOnly = false;
  ReportSort _sort = _defaultSort;

  /// Cloisonnement par pays : code ISO du pays de l'utilisateur (alimenté par
  /// `RegionProvider.activeCountry`). Quand il est défini, on ne montre que les
  /// coupures de ce pays. `null` = pas de cloisonnement. Les reports sans
  /// `countryCode` (données héritées) restent visibles (non destructif).
  String? _countryFilter;

  /// Définit le pays actif (ISO). Sans effet si inchangé. **Re-souscrit** le
  /// flux temps réel : la fenêtre `limit` est désormais bornée par pays
  /// **côté serveur** (voir [ReportService.watchReports]), donc changer de pays
  /// doit relancer la requête (sinon on garderait la fenêtre de l'ancien pays).
  void setCountryFilter(String? iso) {
    final next = (iso == null || iso.isEmpty) ? null : iso.toUpperCase();
    if (next == _countryFilter) return;
    _countryFilter = next;
    // Nouvelle requête bornée par pays : on repart d'une fenêtre propre.
    _limit = AppConstants.reportsPageSize;
    _loading = true;
    _sub.cancel();
    _subscribe();
    notifyListeners();
  }

  /// Filtre service public (élec / eau / null = Tout). Alimenté par
  /// `RegionProvider.serviceFilter` via le proxy d'`AuthGate`. **Filtrage
  /// client-side** (contrairement au pays, désormais borné côté serveur) — pas
  /// d'index Firestore à créer, volume par pays OK au MVP.
  ServiceType? _serviceFilter;

  ServiceType? get serviceFilter => _serviceFilter;

  void setServiceFilter(ServiceType? value) {
    if (value == _serviceFilter) return;
    _serviceFilter = value;
    notifyListeners();
  }

  /// Mode admin « monde » : ignore le cloisonnement pays **ET** la proximité
  /// (sinon le filtre « à proximité » masquerait les coupures lointaines). Par
  /// défaut `false` → comportement normal (proximité respectée).
  bool _worldwide = false;

  void setWorldwide(bool value) {
    if (value == _worldwide) return;
    _worldwide = value;
    notifyListeners();
  }

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
  AppError? get error => _error;
  bool get submitting => _submitting;

  String get query => _query;
  OutageStatus? get statusFilter => _statusFilter;
  bool get onlyMine => _onlyMine;
  bool get nearOnly => _nearOnly;
  bool get nearLoading => _nearLoading;
  ReportSort get sort => _sort;

  /// Vrai si l'utilisateur a modifié les filtres au-delà des valeurs par
  /// défaut (la proximité, qui est un mode par défaut, n'est pas comptée ici).
  bool get hasActiveFilters =>
      _query.isNotEmpty ||
      _statusFilter != _defaultStatus ||
      _onlyMine ||
      _sort != _defaultSort;
  // `_serviceFilter` est **exclu** de `hasActiveFilters` : c'est une vue
  // persistée (via RegionProvider) toujours visible dans le segmented control
  // — pas un filtre transitoire à exposer dans le bandeau « Filtres actifs ».

  /// Liste filtrée + triée selon l'état courant des filtres.
  ///
  /// En mode « à proximité », la base est le résultat de la requête bornée par
  /// geohash (déjà filtrée par distance) ; sinon, le flux temps réel paginé.
  List<Report> get filteredReports {
    final q = _query.trim().toLowerCase();
    // En mode « monde » (admin), on ignore la proximité pour tout afficher.
    final base =
        (_nearOnly && !_worldwide)
            ? (_nearResults ?? const <Report>[])
            : _reports;
    final list =
        base.where((r) {
          // Cloisonnement pays STRICT : un utilisateur ne voit que les coupures
          // de son pays. Tout report dont le pays ne correspond pas (y compris
          // sans countryCode) est exclu. `_countryFilter == null` = mode admin
          // « monde » (aucun cloisonnement). Les anciennes données ont été
          // backfillées (scripts/backfillCountryCode.cjs).
          if (_countryFilter != null &&
              r.location.countryCode != _countryFilter) {
            return false;
          }
          if (_serviceFilter != null && r.serviceType != _serviceFilter) {
            return false;
          }
          if (_statusFilter != null && r.status != _statusFilter) return false;
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

  /// Nombre de coupures **en cours** dans le périmètre courant (pays + service),
  /// indépendamment des filtres transitoires (statut / proximité / recherche /
  /// « mes signalements »). Alimente le bandeau d'activité. S'appuie sur le flux
  /// temps réel (`_reports`), les archivées en étant déjà exclues.
  int get activeInScopeCount {
    return _reports.where((r) {
      if (r.status != OutageStatus.ongoing) return false;
      if (_countryFilter != null && r.location.countryCode != _countryFilter) {
        return false;
      }
      if (_serviceFilter != null && r.serviceType != _serviceFilter) {
        return false;
      }
      return true;
    }).length;
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

  void toggleOnlyMine() {
    _onlyMine = !_onlyMine;
    // « Mes signalements » et « À proximité » sont mutuellement exclusifs.
    if (_onlyMine && _nearOnly) {
      setNearOnly(false); // désactive la proximité (et notifie)
    }
    notifyListeners();
  }

  void setSort(ReportSort value) {
    _sort = value;
    notifyListeners();
  }

  /// Active/désactive le filtre de proximité. Retourne un [AppError]
  /// si la position n'a pas pu être obtenue.
  Future<AppError?> setNearOnly(bool value) async {
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
      _onlyMine = false; // exclusif avec « mes signalements »
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
      return e.code;
    } catch (_) {
      _resetNear();
      return AppError.locationUnavailable;
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
  /// On en profite aussi pour mettre à jour le geohash du device si la
  /// localisation est autorisée (best-effort, async non bloquante).
  Future<void> refresh() async {
    _refreshDeviceGeohashIfPossible();
    if (_nearOnly && _nearCenter != null) {
      await _refreshNear();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Wrapper défensif sur [NotificationService.instance] : ignore toute
  /// exception (Firebase non initialisé en tests, permissions absentes…) —
  /// le ciblage des notifs reste opérationnel grâce au fallback
  /// `homeLocation.city` côté Cloud Function.
  void _refreshDeviceGeohashFrom(GeoPosition position) {
    try {
      unawaited(NotificationService.instance.refreshGeohashFrom(position));
    } catch (_) {
      /* ignore */
    }
  }

  void _refreshDeviceGeohashIfPossible() {
    try {
      unawaited(NotificationService.instance.refreshGeohashIfPossible());
    } catch (_) {
      /* ignore */
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
    _onlyMine = false;
    _sort = _defaultSort;
    notifyListeners();
    if (!_nearOnly) _applyDefaultProximity();
  }

  /// « Tout voir » (bannière de la Liste/Carte) : enlève les filtres
  /// utilisateur **ET** la proximité (le cloisonnement par pays reste). Diffère
  /// de [clearFilters] qui, lui, **réactive** la proximité par défaut.
  Future<void> showAll() async {
    _query = '';
    _statusFilter = _defaultStatus;
    _onlyMine = false;
    _sort = _defaultSort;
    await setNearOnly(false); // désactive la proximité et notifie
  }

  String? get _uid => _auth.currentUser?.uid;
  String? get currentUid => _uid;

  bool isAuthor(Report report) => report.userId == _uid;

  /// Retourne la coupure correspondante dans la liste courante (flux temps réel
  /// ou résultats de proximité), sinon null.
  /// Flux d'un report par id — repli pour l'écran détail quand le report n'est
  /// pas dans la liste temps réel (notification, anti-doublon, lien profond).
  Stream<Report?> watchReport(String id) => _service.watchReport(id);

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
  /// sinon un [AppError]. Le [serviceType] est porté par le report et
  /// permet la différenciation UI (couleurs/marqueurs) + le filtre liste/carte.
  Future<AppError?> submitReport({
    String? description,
    String? authorUsername,
    ServiceType serviceType = ServiceType.electricity,
  }) async {
    final uid = _uid;
    if (uid == null) return AppError.notLoggedIn;

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
        serviceType: serviceType,
        position: loc.position,
        location: loc.area,
        description:
            (description?.trim().isEmpty ?? true) ? null : description!.trim(),
        authorUsername: authorUsername,
        geohash: encodeGeohash(loc.position.lat, loc.position.lng),
      );
      await _service.createReport(report);
      // En mode proximité (requête ponctuelle), on resynchronise tout de suite
      // pour que le nouveau signalement apparaisse sans attendre le refresh.
      if (_nearOnly) await _refreshNear();
      // Profite de la position GPS qu'on vient d'utiliser pour rafraîchir le
      // geohash du device — sans déclencher de nouvelle requête GPS. Wrappé
      // dans un try/catch défensif (NotificationService.instance peut taper
      // Firebase en environnement de test).
      _refreshDeviceGeohashFrom(loc.position);
      return null;
    } on LocationException catch (e) {
      return e.code;
    } catch (_) {
      return AppError.reportSubmitFailed;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  static const Distance _distance = Distance();

  /// Coupure « en cours » la plus proche de [pos] dans le rayon, sinon null.
  ///
  /// Si [serviceType] est fourni, **ne considère que les coupures du même
  /// service** : une coupure d'électricité ne « bloque » pas un signalement
  /// d'eau dans la même zone (ce sont des incidents distincts).
  Report? findNearbyOngoing(
    GeoPosition pos, {
    double radiusMeters = AppConstants.duplicateRadiusMeters,
    ServiceType? serviceType,
  }) {
    final origin = LatLng(pos.lat, pos.lng);
    Report? best;
    double bestDistance = double.infinity;
    for (final report in _reports) {
      if (report.status != OutageStatus.ongoing) continue;
      if (serviceType != null && report.serviceType != serviceType) continue;
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

  /// Geohash grossier du votant attaché à un vote (confirm / restore).
  /// **Best-effort STRICT** : ne déclenche AUCUNE demande de permission (n'utilise
  /// la position que si la localisation est **déjà** autorisée) et est borné à
  /// quelques secondes. Objectif : un vote ne doit JAMAIS être bloqué, ralenti
  /// ou mis en échec à cause de la localisation. Renvoie `null` sinon.
  Future<String?> _voteGeohash() async => (await _votePosition())?.geohash;

  /// Variante de [_voteGeohash] qui renvoie **aussi** la position exacte
  /// (lat/lng), nécessaire au ciblage 500 m des notifications de proximité
  /// déclenchées par une confirmation (Cloud Function `onConfirmationCreated`).
  /// Mêmes garanties best-effort STRICT : jamais de demande de permission,
  /// borné à quelques secondes, `null` en cas d'indisponibilité.
  Future<({String geohash, double lat, double lng})?> _votePosition() async {
    try {
      if (await _location.checkAccess() != LocationAccess.granted) return null;
      final loc = await _location.getCurrentLocation().timeout(
        const Duration(seconds: 4),
      );
      return (
        geohash: encodeGeohash(loc.position.lat, loc.position.lng),
        lat: loc.position.lat,
        lng: loc.position.lng,
      );
    } catch (_) {
      return null;
    }
  }

  /// État d'accès à la localisation (sans déclencher la demande système).
  Future<LocationAccess> checkLocationAccess() => _location.checkAccess();

  /// Position courante pour AFFICHAGE (formulaire) — best-effort, sans état
  /// `submitting` ni demande système. `null` si refusée/indisponible.
  Future<LocationResult?> currentLocation() async {
    try {
      if (await _location.checkAccess() != LocationAccess.granted) return null;
      return await _location.getCurrentLocation();
    } catch (_) {
      return null;
    }
  }

  /// Géocode une position décrite pour AFFICHAGE/validation immédiate dans le
  /// formulaire — `null` si le lieu est introuvable. La création passe ensuite
  /// par [prepareReportFromDescription] (mêmes garanties anti-doublon).
  Future<LocationResult?> locateDescription(String query) async {
    try {
      return await _location.locationFromDescription(query);
    } catch (_) {
      return null;
    }
  }

  /// Ouvre les réglages système de l'app.
  Future<void> openLocationSettings() => _location.openSettings();

  /// Récupère la position et cherche un éventuel doublon proche.
  /// [serviceType] cible la détection au service du futur signalement —
  /// sans ça, signaler une coupure d'eau près d'une coupure d'électricité
  /// ouvre la modale anti-doublon à tort.
  Future<PrepareOutcome> prepareReport({ServiceType? serviceType}) async {
    if (_uid == null) {
      return const PrepareOutcome(error: AppError.notLoggedIn);
    }
    _submitting = true;
    notifyListeners();
    try {
      final loc = await _location.getCurrentLocation();
      final draft = ReportDraft(position: loc.position, area: loc.area);
      return PrepareOutcome(
        draft: draft,
        nearby: findNearbyOngoing(loc.position, serviceType: serviceType),
      );
    } on LocationException catch (e) {
      return PrepareOutcome(error: e.code);
    } catch (_) {
      return const PrepareOutcome(error: AppError.locationUnavailable);
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Prépare un signalement à partir d'une **position décrite** (sans GPS) :
  /// [query] = quartier / ville / adresse, géocodé en coordonnées. Mêmes
  /// garanties que [prepareReport] (draft + détection de doublon à proximité du
  /// point résolu). Renvoie `AppError.locationNotFound` si la description ne
  /// correspond à aucun lieu.
  Future<PrepareOutcome> prepareReportFromDescription(
    String query, {
    ServiceType? serviceType,
  }) async {
    if (_uid == null) {
      return const PrepareOutcome(error: AppError.notLoggedIn);
    }
    _submitting = true;
    notifyListeners();
    try {
      final loc = await _location.locationFromDescription(query);
      final draft = ReportDraft(position: loc.position, area: loc.area);
      return PrepareOutcome(
        draft: draft,
        nearby: findNearbyOngoing(loc.position, serviceType: serviceType),
      );
    } on LocationException catch (e) {
      return PrepareOutcome(error: e.code);
    } catch (_) {
      return const PrepareOutcome(error: AppError.locationNotFound);
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
  /// [reportedAt] = date/heure de **constatation** saisie par l'utilisateur
  /// (facultatif) ; `null` → l'horodatage serveur (« maintenant ») est utilisé.
  Future<AppError?> createFromDraft(
    ReportDraft draft, {
    String? description,
    String? mediaUrl,
    String? authorUsername,
    ServiceType serviceType = ServiceType.electricity,
    DateTime? reportedAt,
    String? countryOverrideIso,
  }) async {
    final uid = _uid;
    if (uid == null) return AppError.notLoggedIn;
    _submitting = true;
    notifyListeners();
    try {
      // Pays choisi dans les Paramètres (dev/staging uniquement — null en
      // prod) : le signalement est rattaché au pays SÉLECTIONNÉ plutôt qu'au
      // pays géocodé, pour qu'un signalement de QA reste visible dans la
      // liste consultée. Le formulaire affiche un bandeau d'information
      // quand ce pays diffère du pays détecté.
      var area = draft.area;
      final iso = countryOverrideIso?.toUpperCase();
      if (iso != null && iso.isNotEmpty && iso != area.countryCode) {
        area = GeoArea(
          country: countryLabelForIso(iso) ?? iso,
          countryCode: iso,
          region: area.region,
          city: area.city,
          neighborhood: area.neighborhood,
        );
      }
      final report = Report(
        id: '',
        userId: uid,
        status: OutageStatus.ongoing,
        // Tout signalement citoyen est une coupure imprévue.
        type: OutageType.unplanned,
        serviceType: serviceType,
        position: draft.position,
        location: area,
        description:
            (description?.trim().isEmpty ?? true) ? null : description!.trim(),
        mediaUrl: mediaUrl,
        authorUsername: authorUsername,
        geohash: encodeGeohash(draft.position.lat, draft.position.lng),
        reportedAt: reportedAt,
      );
      await _service.createReport(report);
      unawaited(markAnonymousActivity(_auth.currentUser));
      AnalyticsService.instance.logReportCreated();
      // En mode proximité (requête ponctuelle), on resynchronise tout de suite
      // pour que le nouveau signalement apparaisse sans attendre le refresh.
      if (_nearOnly) await _refreshNear();
      // Refresh geohash device (sans nouvelle requête GPS, on a déjà la position).
      _refreshDeviceGeohashFrom(draft.position);
      return null;
    } catch (_) {
      return AppError.reportSubmitFailed;
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
      // Position du confirmeur (geohash grossier + lat/lng exact) en best-effort
      // STRICT (ne bloque ni ne fait échouer le vote — cf. [_votePosition]). Le
      // lat/lng exact alimente le ciblage 500 m des notifications côté serveur.
      final vote = await _votePosition();
      await _service.confirmReport(
        reportId,
        uid,
        geohash: vote?.geohash,
        lat: vote?.lat,
        lng: vote?.lng,
      );
      _myConfirmedIds.add(reportId);
      // Un vote vaut réponse au prompt d'ouverture : ne plus solliciter.
      _persistDismissedPrompt(reportId);
      unawaited(markAnonymousActivity(_auth.currentUser));
      AnalyticsService.instance.logReportConfirmed();
      // En mode proximité (requête ponctuelle), on resynchronise tout de suite.
      if (_nearOnly) await _refreshNear();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Répond « Non, pas de coupure chez moi » au prompt d'ouverture. Signal
  /// négatif (délimite l'emprise de la coupure) — ne touche aucun compteur.
  /// Symétrique à [confirm] pour les garanties (best-effort position, jamais
  /// bloquant) ; enregistre aussi la réponse comme dismissal du prompt.
  Future<bool> deny(String reportId) async {
    final uid = _uid;
    if (uid == null) return false;
    // Garde : l'auteur ne « dément » pas sa propre coupure (il l'archive).
    if (reportById(reportId)?.userId == uid) return false;
    try {
      final vote = await _votePosition();
      await _service.denyReport(
        reportId,
        uid,
        geohash: vote?.geohash,
        lat: vote?.lat,
        lng: vote?.lng,
      );
      _persistDismissedPrompt(reportId);
      unawaited(markAnonymousActivity(_auth.currentUser));
      AnalyticsService.instance.logReportDenied();
      return true;
    } catch (_) {
      // Même en cas d'échec réseau, on n'insiste pas : le prompt est écarté.
      _persistDismissedPrompt(reportId);
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

  /// Archive (soft-delete) un signalement. Réservé à l'auteur côté UI ; les
  /// règles Firestore valident côté serveur. Disparaît immédiatement de tous
  /// les flux (filtrés côté client) ; sera supprimé définitivement par le cron
  /// `purgeArchivedReports`.
  Future<bool> archive(String reportId, {String? reason}) async {
    final uid = _uid;
    if (uid == null) return false;
    // Garde-fou client : seul l'auteur peut archiver son report.
    if (reportById(reportId)?.userId != uid) return false;
    try {
      await _service.archiveReport(reportId, reason: reason);
      if (_nearOnly) await _refreshNear();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Déclare « le courant est revenu chez moi » pour cette coupure. Symétrique
  /// à [confirm], y compris pour l'auteur du report (qui devient un confirmant
  /// comme les autres). L'auto-résolution est portée par la Cloud Function
  /// `onRestorationCreated`.
  Future<bool> markRestored(String reportId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      // Geohash grossier du votant, en best-effort STRICT (ne bloque ni ne fait
      // échouer la déclaration — cf. [_voteGeohash]).
      final geohash = await _voteGeohash();
      await _service.markRestored(reportId, uid, geohash: geohash);
      _myRestoredIds.add(reportId);
      unawaited(markAnonymousActivity(_auth.currentUser));
      AnalyticsService.instance.logReportRestored();
      if (_nearOnly) await _refreshNear();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Stream<List<Restoration>> watchRestorations(String reportId) =>
      _service.watchRestorations(reportId);

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    _nearTimer?.cancel();
    super.dispose();
  }
}
