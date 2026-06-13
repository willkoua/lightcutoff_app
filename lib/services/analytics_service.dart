import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Encapsule Firebase Analytics : un point unique pour journaliser les
/// événements clés du **funnel** (inscription, signalement, confirmation, …).
///
/// Choix d'architecture : comme [NotificationService] et Crashlytics, c'est un
/// **service transverse** (pas une donnée métier) → singleton `instance` plutôt
/// que le pattern repository/provider. Les écrans/providers appellent les
/// méthodes typées ci-dessous ; aucune chaîne d'event n'est dispersée dans l'UI.
///
/// Confidentialité : **aucune PII** dans les paramètres. La collecte est
/// **désactivée en dev** (émulateurs) pour ne pas polluer les métriques, et
/// active en staging/prod (cf. [init]).
class AnalyticsService {
  AnalyticsService({FirebaseAnalytics? analytics}) : _injected = analytics;

  /// Singleton partagé (init dans `main.dart`, usage partout ailleurs).
  static AnalyticsService? _instance;
  static AnalyticsService get instance => _instance ??= AnalyticsService();

  /// Permet aux tests d'injecter un faux à la place du singleton.
  @visibleForTesting
  static set instance(AnalyticsService value) => _instance = value;

  // Résolu paresseusement : ne JAMAIS toucher `FirebaseAnalytics.instance` dans
  // le constructeur (il exige Firebase initialisé → casserait les tests et les
  // flux où l'analytics est secondaire). Tout accès passe par un try/catch.
  FirebaseAnalytics? _injected;
  FirebaseAnalytics get _analytics => _injected ??= FirebaseAnalytics.instance;

  /// Observer à brancher sur `MaterialApp.navigatorObservers` → journalise
  /// automatiquement les `screen_view` lors des navigations nommées.
  late final FirebaseAnalyticsObserver observer = FirebaseAnalyticsObserver(
    analytics: _analytics,
  );

  /// À appeler une fois au démarrage : coupe la collecte en dev, l'active
  /// ailleurs. Idempotent.
  Future<void> init() async {
    try {
      await _analytics.setAnalyticsCollectionEnabled(!AppConfig.isDev);
    } catch (_) {
      // L'analytics ne doit jamais bloquer le démarrage.
    }
  }

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (AppConfig.isDev) return; // double garde : pas d'I/O analytics en dev.
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (_) {
      // L'analytics ne doit JAMAIS casser un flux utilisateur.
    }
  }

  // --- Événements du funnel (sans PII) -------------------------------------

  Future<void> logSignUp() async {
    if (AppConfig.isDev) return;
    try {
      await _analytics.logSignUp(signUpMethod: 'email');
    } catch (_) {
      // idem : ne jamais propager une erreur d'analytics.
    }
  }

  Future<void> logReportCreated() => _log('report_created');

  Future<void> logReportConfirmed() => _log('report_confirmed');

  Future<void> logReportRestored() => _log('report_restored');

  /// L'utilisateur a ouvert l'onglet des coupures planifiées (Eneo).
  Future<void> logPlannedOutagesViewed() => _log('planned_outages_viewed');

  /// L'utilisateur (dé)suit un quartier pour les alertes planifiées.
  Future<void> logQuartierFollowed({required bool following}) =>
      _log('quartier_follow_toggled', {'following': following});
}
