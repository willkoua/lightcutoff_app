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

  /// Mode capture d'écran (Play Store) : masque la bannière d'environnement et
  /// les outils dev pour des captures « propres », sans rebrancher la prod.
  /// Activer via `--dart-define=SCREENSHOT_MODE=true` (build staging).
  static const bool screenshotMode = bool.fromEnvironment('SCREENSHOT_MODE');

  /// Masque UNIQUEMENT la bannière d'environnement (DEV/STAGING) en gardant les
  /// outils dev (sélecteur de pays…) : build « tournage vidéo » — on configure
  /// ET on filme avec le même APK, sans bannière à l'écran.
  /// Activer via `--dart-define=HIDE_ENV_BANNER=true` (build staging).
  static const bool hideEnvBanner = bool.fromEnvironment('HIDE_ENV_BANNER');

  /// Outils de dev (sélecteurs langue, pays/compagnie…) : visibles partout
  /// **sauf en prod** — tout ce qu'on voit en dev doit exister en staging.
  /// Masqués aussi en [screenshotMode].
  static bool get showDevTools => !isProd && !screenshotMode;

  /// Base des liens de partage public (`{base}/s/{reportId}`) — TOUJOURS le
  /// domaine officiel (décision 2026-08-08) : la CF prod `renderReportShare`
  /// lit njuka-prod puis retombe sur lightcutoff-dev, les liens partagés
  /// depuis un build de test restent donc valides ET à la marque.
  static String get shareBaseUrl => 'https://njuka.app';

  /// Affiche le bouton « Continuer avec Google ». **Désactivé** tant que la
  /// config Firebase n'est pas faite (provider Google activé + empreintes SHA-1
  /// debug/release/Play App Signing + `google-services.json` régénéré — voir
  /// `tasks/SETUP-AUTH-GOOGLE.md`). Sans cette config, le bouton planterait
  /// (`ApiException: 10`).
  ///
  /// **PROD UNIQUEMENT depuis le jour J OAuth (2026-07-28)** : les clients
  /// OAuth Android (package + SHA) ont été basculés de `lightcutoff-dev` vers
  /// `njuka-prod` — contrainte Google : un seul projet par combinaison. En
  /// dev/staging le bouton échouerait (`ApiException: 10`) → masqué.
  static bool get enableGoogleSignIn => isProd;

  /// Autorise l'ajout d'un média (photo/GIF) au signalement. **DÉSACTIVÉ le
  /// 2026-07-30** : réduction de la surface UGC avant publication stores
  /// (pas de pipeline de modération d'images). Les médias des reports
  /// existants restent affichés. Réactiver quand une modération existera.
  static const bool enableReportMedia = false;

  /// Affiche le bouton « Continuer avec Apple » — **iOS uniquement** (exigence
  /// App Store 4.8 : obligatoire dès qu'une connexion tierce est proposée).
  /// Nécessite : capability « Sign in with Apple » (Xcode) + provider Apple
  /// activé dans Firebase Authentication.
  static bool get enableAppleSignIn => !kIsWeb && Platform.isIOS;

  /// Affiche le bouton « Continuer avec Facebook ». **Désactivé** tant que la
  /// config n'est pas faite (app Facebook + provider Facebook activé dans
  /// Firebase + clé secrète + key hashes Android + client token). Passer à
  /// `true` puis rebuild une fois la config prête.
  static const bool enableFacebookSignIn = true;

  /// Étiquette de la bannière d'environnement (`null` = pas de bannière, prod).
  /// `null` aussi en [screenshotMode] (captures propres) et [hideEnvBanner]
  /// (tournage vidéo : bannière cachée, outils dev conservés).
  static String? get envBannerLabel {
    if (screenshotMode || hideEnvBanner) return null;
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
