import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_constants.dart';
import '../models/device.dart';
import '../models/geo.dart';
import '../repositories/device_repository.dart';
import '../utils/crash_reporter.dart';
import 'device_service.dart';

/// Encapsule l'accès au SDK Firebase Cloud Messaging + l'affichage des
/// notifications via `flutter_local_notifications`, et l'orchestration de
/// l'enregistrement du device dans Firestore.
///
/// Cycle de vie :
/// - [init] est appelée une seule fois au démarrage (depuis `main.dart`) ;
///   elle crée le channel Android, prépare les listeners et traite le cas
///   où l'app a été ouverte depuis une notif (état terminé).
/// - [registerForUser] / [unregister] sont déclenchés par l'AuthProvider
///   selon le statut de connexion.
class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    DeviceRepository? deviceRepository,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _devices = deviceRepository ?? DeviceService(),
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  /// Singleton partagé entre `main.dart` (init) et `AuthProvider`
  /// (register/unregister). Permet de garantir qu'on parle au même instance
  /// dans toute l'app, sans dépendre d'un Provider.
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService();

  /// Permet aux tests d'injecter un mock à la place du singleton.
  @visibleForTesting
  static set instance(NotificationService value) => _instance = value;

  final FirebaseMessaging _messaging;
  final DeviceRepository _devices;
  final FlutterLocalNotificationsPlugin _localNotifications;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  bool _initialized = false;

  /// Signal de navigation vers un report depuis une notif (tap ou message
  /// d'ouverture). Lu par [MainShell] qui pushera [ReportDetailScreen] depuis
  /// SON scope — celui qui a accès au `ReportProvider` (la navigation directe
  /// via [navigatorKey] casse parce que le provider est scoped sous AuthGate).
  /// Le listener doit remettre la valeur à `null` après consommation.
  final ValueNotifier<String?> pendingReportId = ValueNotifier<String?>(null);

  /// Utilisateur courant (mis à jour par [registerForUser] / [unregister]).
  String? _userId;
  GeoArea _homeLocation = const GeoArea();
  String? _lastToken;

  // ---------------------------------------------------------------------------
  // Initialisation (appelée une fois au démarrage de l'app)
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Initialise le plugin local notifications (icône, callback de tap).
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // 2. Crée le channel Android (sans channel, Android 8+ n'affiche rien).
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          AppConstants.fcmOutageChannelId,
          AppConstants.fcmOutageChannelName,
          description: AppConstants.fcmOutageChannelDescription,
          importance: Importance.high,
        ),
      );
    }

    // 3. iOS : autorise l'affichage des notifs en foreground (alert + son).
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 4. Foreground : Android n'affiche rien par défaut → on relaie via le
    //    plugin local notifications.
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 5. Tap sur la notif quand l'app est en arrière-plan.
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);

    // 6. App lancée DEPUIS une notif (état terminé) : on traite après que le
    //    Navigator soit prêt.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onMessageOpened(initial),
      );
    }

    debugPrint('[FCM] NotificationService initialisé');
  }

  // ---------------------------------------------------------------------------
  // Réception : foreground + tap
  // ---------------------------------------------------------------------------

  /// Foreground : affiche la notif via le plugin local (Android), et propose
  /// un tap (payload = data JSON).
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    debugPrint(
      '[FCM] foreground messageId=${message.messageId} '
      'title="${message.notification?.title}" data=${message.data}',
    );
    final notif = message.notification;
    if (notif == null) return;
    await _localNotifications.show(
      // ID unique stable : hash du messageId pour éviter d'écraser une autre
      // notif déjà affichée.
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.fcmOutageChannelId,
          AppConstants.fcmOutageChannelName,
          channelDescription: AppConstants.fcmOutageChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Tap depuis une notif locale (foreground) → on extrait le payload.
  void _onLocalNotificationTap(NotificationResponse response) {
    final raw = response.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _openReportFromData(data);
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'fcm local notif payload');
    }
  }

  /// Tap depuis une notif FCM en arrière-plan (ou app terminée).
  void _onMessageOpened(RemoteMessage message) {
    debugPrint('[FCM] tap messageId=${message.messageId} data=${message.data}');
    _openReportFromData(message.data);
  }

  /// Émet le reportId à ouvrir via [pendingReportId]. C'est [MainShell] qui
  /// fait le push réel (il a accès au `ReportProvider`).
  void _openReportFromData(Map<String, dynamic> data) {
    final reportId = data['reportId'] as String?;
    if (reportId == null || reportId.isEmpty) return;
    debugPrint('[FCM] pendingReportId=$reportId (relayé à MainShell)');
    pendingReportId.value = reportId;
  }

  // ---------------------------------------------------------------------------
  // Enregistrement / désinscription du device
  // ---------------------------------------------------------------------------

  /// Demande la permission de notifier. Retourne `true` si autorisé (ou
  /// provisoirement autorisé sur iOS).
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Enregistre l'appareil pour [userId] : récupère le token FCM, upserte
  /// `devices/{token}` et écoute les rotations futures.
  Future<void> registerForUser({
    required String userId,
    GeoArea homeLocation = const GeoArea(),
  }) async {
    _userId = userId;
    _homeLocation = homeLocation;

    final granted = await requestPermission();
    if (!granted) {
      debugPrint('[FCM] permission refusée, pas d\'enregistrement');
      return;
    }

    final token = await _messaging.getToken();
    if (token == null) {
      debugPrint('[FCM] getToken() a renvoyé null');
      return;
    }
    await _upsert(token);

    _tokenSub?.cancel();
    _tokenSub = _messaging.onTokenRefresh.listen((newToken) async {
      if (_userId == null) return;
      try {
        if (_lastToken != null && _lastToken != newToken) {
          await _devices.deleteDevice(_lastToken!);
        }
        await _upsert(newToken);
      } catch (e, st) {
        CrashReporter.recordError(e, st, reason: 'fcm token refresh');
      }
    });
  }

  /// Supprime le doc device courant (déconnexion). Échec silencieux.
  Future<void> unregister() async {
    _tokenSub?.cancel();
    _tokenSub = null;
    final token = _lastToken ?? await _messaging.getToken();
    _userId = null;
    _lastToken = null;
    if (token == null) return;
    try {
      await _devices.deleteDevice(token);
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'fcm device unregister');
    }
  }

  Future<void> _upsert(String token) async {
    _lastToken = token;
    final device = Device(
      token: token,
      userId: _userId ?? '',
      platform: _platform(),
      homeLocation: _homeLocation,
      fcmEnabled: true,
    );
    // Imprime le token COMPLET dans les logs en debug — utile pour tester
    // l'envoi de notifs depuis Firebase Console (« Send test message »).
    if (kDebugMode) {
      debugPrint('[FCM] FULL TOKEN (copy this):');
      debugPrint(token);
    }
    try {
      await _devices.upsertDevice(device);
      debugPrint('[FCM] device upserté (token=${_short(token)}, uid=$_userId)');
    } catch (e, st) {
      debugPrint('[FCM] upsert FAILED: $e');
      debugPrint('$st');
      CrashReporter.recordError(e, st, reason: 'fcm device upsert');
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  String _short(String token) =>
      token.length > 12 ? '${token.substring(0, 12)}…' : token;

  /// À appeler dans les tests pour libérer les subscriptions.
  @visibleForTesting
  Future<void> disposeForTest() async {
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
  }
}
