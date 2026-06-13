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

import 'app.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';
import 'services/analytics_service.dart';
import 'services/notification_service.dart';

/// Handler des messages FCM reçus quand l'app est en arrière-plan ou tuée.
/// Doit être une fonction top-level annotée `@pragma('vm:entry-point')` :
/// elle s'exécute dans un isolate dédié, donc on doit ré-initialiser Firebase.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Pas d'affichage manuel ici : avec un payload `notification`, FCM Android
  // affiche déjà la notif automatiquement. On garde ce handler pour les futurs
  // traitements (cache local, badge, etc.).
  debugPrint('[FCM bg] message reçu: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Environnements : dev (émulateurs) et staging partagent le projet Firebase
  // `lightcutoff-dev` (options ci-dessous). Le projet **prod** n'existe pas
  // encore : on échoue bruyamment plutôt que d'écrire en douce dans staging.
  // Le jour venu : créer le projet → `flutterfire configure --project=<prod>
  // --out=lib/firebase_options_prod.dart` → sélectionner les options ici.
  if (AppConfig.isProd) {
    throw StateError(
      'APP_ENV=prod : projet Firebase de production pas encore créé. '
      'Générer firebase_options_prod.dart via flutterfire configure.',
    );
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
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
