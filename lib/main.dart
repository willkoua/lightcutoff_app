import 'package:cloud_firestore/cloud_firestore.dart';
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
