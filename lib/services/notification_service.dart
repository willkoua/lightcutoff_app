import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/geo.dart';
import '../repositories/device_repository.dart';
import '../utils/crash_reporter.dart';
import 'device_service.dart';

/// Encapsule l'accès au SDK Firebase Cloud Messaging et l'orchestration de
/// l'enregistrement / suppression du device courant dans Firestore.
///
/// Le token FCM peut changer dans le temps (rotation Android, réinstallation,
/// changement de SIM) : on écoute [FirebaseMessaging.onTokenRefresh] et on
/// resynchronise le doc `devices/{token}` à chaque rotation pour l'utilisateur
/// courant.
class NotificationService {
  NotificationService({
    FirebaseMessaging? messaging,
    DeviceRepository? deviceRepository,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _devices = deviceRepository ?? DeviceService();

  final FirebaseMessaging _messaging;
  final DeviceRepository _devices;

  StreamSubscription<String>? _tokenSub;

  /// Identifiant de l'utilisateur courant (mis à jour à chaque
  /// [registerForUser] / [unregister]).
  String? _userId;
  GeoArea _homeLocation = const GeoArea();
  String? _lastToken;

  /// Demande la permission de notifier (no-op sur Android <13, pop-up sinon ;
  /// pop-up systématique sur iOS). Retourne `true` si l'utilisateur a accepté
  /// (ou si une autorisation provisoire est en place).
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Enregistre l'appareil pour [userId] : récupère le token FCM, écrit
  /// `devices/{token}` et écoute les rotations futures pour resynchroniser.
  ///
  /// Idempotent : appeler plusieurs fois ne pose pas de problème (le doc est
  /// upserté), mais on annule la précédente souscription si l'utilisateur
  /// change.
  Future<void> registerForUser({
    required String userId,
    GeoArea homeLocation = const GeoArea(),
  }) async {
    _userId = userId;
    _homeLocation = homeLocation;

    // On demande la permission de manière soft : si l'utilisateur refuse,
    // l'enregistrement échoue silencieusement (pas de blocage de l'app).
    final granted = await requestPermission();
    if (!granted) {
      debugPrint('[FCM] permission refusée, on n\'enregistre pas de device');
      return;
    }

    final token = await _messaging.getToken();
    if (token == null) {
      debugPrint('[FCM] getToken() a renvoyé null');
      return;
    }
    await _upsert(token);

    // Écoute des rotations de token : on resynchronise pour le user courant.
    _tokenSub?.cancel();
    _tokenSub = _messaging.onTokenRefresh.listen((newToken) async {
      if (_userId == null) return;
      try {
        // Le token a changé : on supprime l'ancien doc (s'il existait) avant
        // d'enregistrer le nouveau, pour éviter des doublons d'envoi.
        if (_lastToken != null && _lastToken != newToken) {
          await _devices.deleteDevice(_lastToken!);
        }
        await _upsert(newToken);
      } catch (e, st) {
        CrashReporter.recordError(e, st, reason: 'fcm token refresh');
      }
    });
  }

  /// Supprime le doc device courant (déconnexion) et arrête l'écoute des
  /// rotations. Échec silencieux : on ne veut pas bloquer le flow de logout.
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
      // geohash de la résidence : on ne le calcule pas ici (homeLocation
      // est encore stocké sans coordonnées GPS). Phase 4 affinera le ciblage.
      fcmEnabled: true,
    );
    await _devices.upsertDevice(device);
    debugPrint('[FCM] device upserté (token=${_short(token)}, uid=$_userId)');
  }

  String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  /// Tronque le token pour les logs (sécurité).
  String _short(String token) =>
      token.length > 12 ? '${token.substring(0, 12)}…' : token;
}
