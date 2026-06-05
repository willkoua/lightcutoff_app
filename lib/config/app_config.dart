import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Configuration d'environnement de l'app.
///
/// Bascule entre les émulateurs Firebase locaux et Firebase en ligne via :
///   flutter run --dart-define=USE_EMULATOR=true
/// (par défaut : false → Firebase en ligne).
class AppConfig {
  AppConfig._();

  /// Active les émulateurs Firebase locaux quand `true`.
  static const bool useEmulator = bool.fromEnvironment(
    'USE_EMULATOR',
    defaultValue: false,
  );

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
