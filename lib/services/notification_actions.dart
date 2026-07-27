import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant, Locale, PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../config/app_constants.dart';
import '../firebase_options.dart';
import '../utils/geohash.dart';
import 'report_service.dart';

/// Identifiants des boutons d'action des notifications de coupure.
/// Doivent rester stables : ils sont gravés dans les notifs déjà affichées.
const String kNotifActionConfirm = 'njuka_confirm';
const String kNotifActionDeny = 'njuka_deny';

/// Handler des taps sur un **bouton d'action** de notification.
///
/// `showsUserInterface: false` → flutter_local_notifications invoque TOUJOURS
/// ce callback dans un **isolate d'arrière-plan dédié** (même app ouverte),
/// sans lancer l'UI. Il faut donc ré-initialiser Firebase ici. L'utilisateur
/// vote « chez moi aussi » / « pas chez moi » en 1 tap, sans ouvrir l'app.
@pragma('vm:entry-point')
Future<void> notificationActionBackgroundHandler(
  NotificationResponse response,
) async {
  try {
    // Enregistre les plugins à canal de plateforme (geolocator…) dans CET
    // isolate — sans ça, getLastKnownPosition renvoie null et le vote part
    // sans position (compté, mais ne propage pas la tache d'huile).
    DartPluginRegistrant.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await handleNotificationAction(response);
  } catch (e, st) {
    // Pas de Crashlytics garanti dans cet isolate : trace debug uniquement.
    debugPrint('[FCM action] échec: $e\n$st');
  }
}

/// Exécute le vote correspondant à l'action ([kNotifActionConfirm] /
/// [kNotifActionDeny]) pour le report du payload. Firebase doit être
/// initialisé par l'appelant. Idempotent (mêmes garanties que les votes
/// in-app : un doc par uid, transaction côté confirmation).
Future<void> handleNotificationAction(NotificationResponse response) async {
  final action = response.actionId;
  if (action != kNotifActionConfirm && action != kNotifActionDeny) return;
  final raw = response.payload;
  if (raw == null || raw.isEmpty) return;
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final reportId = data['reportId'] as String?;
  if (reportId == null || reportId.isEmpty) return;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    debugPrint('[FCM action] pas d\'utilisateur courant, vote ignoré');
    return;
  }

  // Position best-effort STRICT : dernière position connue uniquement (rapide,
  // aucune demande de permission, pas de GPS actif). `null` si indisponible —
  // le vote passe quand même (position optionnelle, cf. règles).
  double? lat;
  double? lng;
  String? geohash;
  try {
    final pos = await Geolocator.getLastKnownPosition();
    if (pos != null) {
      lat = pos.latitude;
      lng = pos.longitude;
      geohash = encodeGeohash(
        pos.latitude,
        pos.longitude,
        precision: AppConstants.geohashPrecision,
      );
    }
  } catch (_) {
    // Sans position : vote sans épicentre (compté, mais ne propage pas).
  }

  final service = ReportService();
  if (action == kNotifActionConfirm) {
    await service.confirmReport(
      reportId,
      uid,
      geohash: geohash,
      lat: lat,
      lng: lng,
    );
    debugPrint('[FCM action] confirmation enregistrée pour $reportId');
  } else {
    await service.denyReport(
      reportId,
      uid,
      geohash: geohash,
      lat: lat,
      lng: lng,
    );
    debugPrint('[FCM action] démenti enregistré pour $reportId');
  }
}

/// Libellés localisés des actions, utilisables **sans BuildContext** (isolate
/// d'arrière-plan inclus) via la locale système. Repli français si la locale
/// n'est pas supportée.
({String confirm, String deny}) notificationActionLabels(
  Map<String, dynamic> data,
) {
  AppLocalizations l;
  try {
    l = lookupAppLocalizations(PlatformDispatcher.instance.locale);
  } catch (_) {
    l = lookupAppLocalizations(const Locale('fr'));
  }
  final isWater = data['serviceType'] == 'water';
  return (
    confirm: l.promptNearbyYes,
    deny: isWater ? l.promptNearbyNoWater : l.promptNearbyNoElectricity,
  );
}

/// Affiche la notification de coupure (message FCM **data-only**) avec les
/// boutons d'action de vote. Partagée entre le foreground
/// (`NotificationService`) et le handler FCM d'arrière-plan (`main.dart`) —
/// le channel Android existe déjà (créé par `NotificationService.init` à un
/// lancement précédent).
Future<void> showOutageNotification(
  FlutterLocalNotificationsPlugin plugin,
  Map<String, dynamic> data,
) async {
  final title = data['title'] as String?;
  final body = data['body'] as String?;
  if (title == null || body == null) return;
  final labels = notificationActionLabels(data);
  final reportId = data['reportId'] as String? ?? '';

  await plugin.show(
    // ID stable par report : une nouvelle vague pour la même coupure REMPLACE
    // la notif existante au lieu d'empiler (anti-spam).
    reportId.isNotEmpty
        ? reportId.hashCode
        : DateTime.now().millisecondsSinceEpoch,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        AppConstants.fcmOutageChannelId,
        AppConstants.fcmOutageChannelName,
        channelDescription: AppConstants.fcmOutageChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        actions: [
          AndroidNotificationAction(
            kNotifActionConfirm,
            labels.confirm,
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            kNotifActionDeny,
            labels.deny,
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
      // iOS : pas de boutons pour l'instant (nécessite les categories APNs,
      // hors périmètre du test fermé Android).
      iOS: const DarwinNotificationDetails(),
    ),
    payload: jsonEncode(data),
  );
}
