import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Environnements de l'app.
///
/// - [dev]     : émulateurs Firebase **locaux** + outils de dev visibles.
/// - [staging] : projet Firebase en ligne `lightcutoff-dev` + outils de dev
///               visibles (même en build release) — environnement de recette.
/// - [prod]    : projet Firebase de production (à créer) ; outils de dev cachés.
enum AppEnvironment { dev, staging, prod }

/// Configuration d'environnement de l'app.
///
/// Sélection via :
///   flutter run --dart-define=APP_ENV=dev|staging|prod
///
/// Rétro-compatibilité : sans `APP_ENV`, `USE_EMULATOR=true` ≡ `dev`, sinon
/// `staging` (= comportement historique : Firebase en ligne lightcutoff-dev).
class AppConfig {
  AppConfig._();

  static const String _envRaw = String.fromEnvironment(
    'APP_ENV',
    defaultValue: '',
  );

  /// Ancien flag, conservé pour ne pas casser les commandes existantes.
  static const bool _legacyUseEmulator = bool.fromEnvironment(
    'USE_EMULATOR',
    defaultValue: false,
  );

  /// Résolution **pure** (testable) du nom d'environnement.
  @visibleForTesting
  static AppEnvironment parseEnvironment(
    String raw, {
    bool legacyUseEmulator = false,
  }) {
    switch (raw.trim().toLowerCase()) {
      case 'dev':
      case 'development':
        return AppEnvironment.dev;
      case 'staging':
        return AppEnvironment.staging;
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      default:
        return legacyUseEmulator ? AppEnvironment.dev : AppEnvironment.staging;
    }
  }

  /// Environnement actif.
  static AppEnvironment get environment =>
      parseEnvironment(_envRaw, legacyUseEmulator: _legacyUseEmulator);

  static bool get isDev => environment == AppEnvironment.dev;
  static bool get isStaging => environment == AppEnvironment.staging;
  static bool get isProd => environment == AppEnvironment.prod;

  /// Outils de dev (sélecteurs langue, pays/compagnie…) : visibles partout
  /// **sauf en prod** — tout ce qu'on voit en dev doit exister en staging.
  static bool get showDevTools => !isProd;

  /// Étiquette de la bannière d'environnement (`null` = pas de bannière, prod).
  static String? get envBannerLabel {
    switch (environment) {
      case AppEnvironment.dev:
        return 'DEV';
      case AppEnvironment.staging:
        return 'STAGING';
      case AppEnvironment.prod:
        return null;
    }
  }

  /// Les émulateurs Firebase locaux ne servent qu'en [AppEnvironment.dev].
  static bool get useEmulator => isDev;

  /// Hôte des émulateurs (override possible via --dart-define=EMULATOR_HOST=...).
  static const String _hostOverride = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '',
  );

  /// Sur l'émulateur Android, `localhost` de la machine hôte = `10.0.2.2`.
  static String get emulatorHost {
    if (_hostOverride.isNotEmpty) return _hostOverride;
    if (!kIsWeb && Platform.isAndroid) return '10.0.2.2';
    return 'localhost';
  }

  // Ports déclarés dans firebase.json
  static const int authPort = 9099;
  static const int firestorePort = 8080;
  static const int databasePort = 9000;
  static const int storagePort = 9199;

  // --- Carte (tuiles) ---

  /// Clé API Stadia Maps pour les tuiles de la carte. Fournie au build via
  ///   flutter run/build --dart-define=STADIA_API_KEY=xxxxxxxx
  /// Vide par défaut → la carte retombe sur les tuiles OpenStreetMap brutes
  /// (acceptable en dev uniquement ; à NE PAS publier sans clé Stadia).
  ///
  /// Note sécurité : une clé de tuiles est côté client, donc jamais totalement
  /// secrète. La protection réelle = la restreindre (propriété / plafond) dans
  /// le tableau de bord Stadia Maps.
  static const String stadiaApiKey = String.fromEnvironment(
    'STADIA_API_KEY',
    defaultValue: '',
  );

  /// `true` quand une clé Stadia est fournie → tuiles Stadia ; sinon OSM (dev).
  static bool get useStadiaTiles => stadiaApiKey.isNotEmpty;
}
