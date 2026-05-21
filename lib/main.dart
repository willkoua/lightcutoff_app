import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';

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
  debugPrint('NJUKA → émulateurs Firebase ($host)');
}
