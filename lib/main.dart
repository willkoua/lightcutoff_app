import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';
import 'firebase_options_prod.dart' as prod;
import 'services/analytics_service.dart';
import 'services/notification_actions.dart';
import 'services/notification_service.dart';

/// Handler des messages FCM reçus quand l'app est en arrière-plan ou tuée.
/// Doit être une fonction top-level annotée `@pragma('vm:entry-point')` :
/// elle s'exécute dans un isolate dédié, donc on doit ré-initialiser Firebase.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM bg] message reçu: ${message.messageId}');
  // Messages **data-only** (coupures de proximité) : le système n'affiche
  // rien tout seul → on affiche nous-mêmes la notif AVEC les boutons de vote
  // « Chez moi aussi / Pas chez moi » (1 tap, sans ouvrir l'app). Les messages
  // avec bloc `notification` (coupures planifiées) restent affichés par FCM.
  if (message.notification == null) {
    await showOutageNotification(
      FlutterLocalNotificationsPlugin(),
      message.data,
    );
  }
}

/// Vrai si [error] est une erreur réseau **transitoire** (perte de connexion,
/// timeout, reset, host injoignable) — typiquement un échec de chargement de
/// tuile de carte (`flutter_map` via `package:http`, qui lève une
/// `ClientException` encapsulant souvent une `SocketException`). Ces erreurs ne
/// sont pas des crashs : on évite de les remonter à Crashlytics comme fatales.
bool _isTransientNetworkError(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException) {
    return true;
  }
  // `package:http` n'est pas une dépendance directe : on identifie sa
  // `ClientException` (et les SocketException encapsulées) par le texte.
  final text = error.toString().toLowerCase();
  return text.contains('clientexception') ||
      text.contains('socketexception') ||
      text.contains('connection reset') ||
      text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('software caused connection abort') ||
      text.contains('failed host lookup');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Environnements : dev (émulateurs) et staging partagent le projet Firebase
  // `lightcutoff-dev` (firebase_options.dart) ; la **prod** utilise le projet
  // `njuka-prod` (firebase_options_prod.dart, généré par flutterfire configure
  // le 2026-07-24). ⚠️ Un build prod exige AUSSI les fichiers natifs prod :
  // `tool/use_env.sh prod` échange google-services.json /
  // GoogleService-Info.plist (variantes .prod conservées à côté).
  await Firebase.initializeApp(
    options:
        AppConfig.isProd
            ? prod.DefaultFirebaseOptions.currentPlatform
            : DefaultFirebaseOptions.currentPlatform,
  );

  // App Check : atteste que les requêtes viennent bien de l'app authentique
  // (anti-abus sur Firestore / Storage / Auth / Functions). Doit être activé
  // juste après l'init Firebase, AVANT toute autre utilisation d'un produit
  // Firebase (Firestore via NotificationService, etc.).
  //
  // - Debug : provider `debug` → un jeton de debug est imprimé dans les logs
  //   au 1er lancement ; l'enregistrer dans Firebase Console → App Check →
  //   « Gérer les jetons de debug » (sinon les requêtes sont rejetées quand
  //   l'enforcement est actif).
  // - Release : Play Integrity (Android) ; App Attest avec repli DeviceCheck
  //   (iOS) — le repli est indispensable car le plancher est iOS 13 alors
  //   qu'App Attest exige iOS 14+.
  await FirebaseAppCheck.instance.activate(
    providerAndroid:
        kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
    providerApple:
        kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );

  // Persistance hors-ligne Firestore : activée par défaut sur mobile, rendue
  // explicite ici pour documenter l'intention (lectures servies depuis le cache
  // et écritures simples mises en file quand le réseau manque). Doit être défini
  // avant tout usage de Firestore.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Crash reporting : collecte active uniquement hors debug.
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = (details) {
    // Échec réseau transitoire (ex. tuile de carte OSM dont la connexion est
    // resettée) : ce n'est PAS un crash. On l'enregistre en non-fatal pour
    // info, au lieu d'inonder Crashlytics de faux crashs fatals.
    if (_isTransientNetworkError(details.exception)) {
      crashlytics.recordError(
        details.exception,
        details.stack,
        reason: 'réseau transitoire (non fatal)',
        fatal: false,
      );
      return;
    }
    crashlytics.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(
      error,
      stack,
      fatal: !_isTransientNetworkError(error),
    );
    return true;
  };

  if (AppConfig.useEmulator) {
    await _connectToEmulators();
  }

  // Analytics : collecte coupée en dev, active en staging/prod (funnel).
  await AnalyticsService.instance.init();

  // Handler background FCM : enregistré AVANT runApp pour qu'il survive aux
  // messages reçus avant que l'UI ne soit prête.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Channel Android + listeners foreground/tap + check getInitialMessage.
  await NotificationService.instance.init();

  runApp(const NjukaApp());
}

Future<void> _connectToEmulators() async {
  final host = AppConfig.emulatorHost;
  await FirebaseAuth.instance.useAuthEmulator(host, AppConfig.authPort);
  FirebaseFirestore.instance.useFirestoreEmulator(
    host,
    AppConfig.firestorePort,
  );
  FirebaseDatabase.instance.useDatabaseEmulator(host, AppConfig.databasePort);
  await FirebaseStorage.instance.useStorageEmulator(
    host,
    AppConfig.storagePort,
  );
  debugPrint('NJUKA → émulateurs Firebase ($host)');
}
