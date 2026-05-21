import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Point d'entrée unique pour le reporting d'erreurs / logs.
/// En debug : sortie console. En release : envoyé à Firebase Crashlytics.
class CrashReporter {
  CrashReporter._();

  static FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;

  /// Enregistre une erreur non fatale.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
  }) async {
    if (kDebugMode) {
      debugPrint('CrashReporter [${reason ?? 'error'}] : $error');
      return;
    }
    await _crashlytics.recordError(error, stack, reason: reason);
  }

  /// Trace de contexte (breadcrumb).
  static void log(String message) {
    if (kDebugMode) {
      debugPrint('CrashReporter: $message');
    } else {
      _crashlytics.log(message);
    }
  }

  /// Associe les rapports à l'utilisateur courant (ou les dissocie si null).
  static Future<void> setUser(String? uid) {
    if (kDebugMode) return Future.value();
    return _crashlytics.setUserIdentifier(uid ?? '');
  }
}
