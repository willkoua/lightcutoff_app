import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_error.dart';
import '../models/app_user.dart';
import '../models/geo.dart';
import '../repositories/auth_repository.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/crash_reporter.dart';

enum AuthStatus {
  unknown,
  authenticated,
  awaitingVerification,
  unauthenticated,
}

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repository, NotificationService? notifications})
    : _service = repository ?? AuthService(),
      // Singleton partagé avec `main.dart` (init du service) pour que
      // l'enregistrement du device parle au même instance que l'init.
      _notifications = notifications ?? NotificationService.instance {
    _sub = _service.authStateChanges.listen(_onAuthStateChanged);
  }

  final AuthRepository _service;
  final NotificationService _notifications;
  late final StreamSubscription<User?> _sub;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _profile;
  bool _busy = false;
  AppError? _error;

  AuthStatus get status => _status;
  AppUser? get profile => _profile;
  bool get busy => _busy;
  AppError? get error => _error;

  Future<void> _onAuthStateChanged(User? user) async {
    CrashReporter.setUser(user?.uid);
    if (user == null) {
      _profile = null;
      _status = AuthStatus.unauthenticated;
      // Désinscription du device pour ne plus recevoir de notifs.
      unawaited(_notifications.unregister());
    } else if (!user.emailVerified) {
      _profile = null;
      _status = AuthStatus.awaitingVerification;
    } else {
      _profile = await _service.fetchProfile(user.uid);
      _status = AuthStatus.authenticated;
      // Enregistre le device pour les notifs push (idempotent, ne bloque pas).
      unawaited(
        _notifications.registerForUser(
          userId: user.uid,
          homeLocation: _profile?.homeLocation ?? const GeoArea(),
        ),
      );
    }
    notifyListeners();
  }

  String? get pendingEmail => _service.currentUser?.email;

  Future<void> resendVerificationEmail() => _service.sendEmailVerification();

  /// Recharge l'utilisateur ; si l'email est vérifié, bascule sur authenticated.
  Future<bool> refreshVerification() async {
    await _service.reloadUser();
    final user = _service.currentUser;
    if (user != null && user.emailVerified) {
      _profile = await _service.fetchProfile(user.uid);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> login({required String identifier, required String password}) {
    return _run(
      () => _service.signInWithIdentifier(
        identifier: identifier,
        password: password,
      ),
    );
  }

  /// `true` si le pseudo est disponible (best-effort : renvoie `true` en cas
  /// d'erreur réseau pour ne pas bloquer la saisie).
  Future<bool> isUsernameAvailable(String username) async {
    try {
      return await _service.isUsernameAvailable(username);
    } catch (_) {
      return true;
    }
  }

  Future<bool> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? phoneNumber,
    DateTime? birthDate,
  }) {
    return _run(
      () => _service.register(
        firstName: firstName,
        lastName: lastName,
        username: username,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
        birthDate: birthDate,
      ),
    );
  }

  Future<bool> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) {
    return _run(
      () => _service.changeEmail(
        newEmail: newEmail,
        currentPassword: currentPassword,
      ),
    );
  }

  Future<bool> changePassword({
    required String newPassword,
    required String currentPassword,
  }) {
    return _run(
      () => _service.changePassword(
        newPassword: newPassword,
        currentPassword: currentPassword,
      ),
    );
  }

  Future<void> logout() => _service.signOut();

  /// Suppression définitive du compte. Au succès, la déconnexion serveur fait
  /// basculer [status] sur `unauthenticated` via le listener d'auth (l'AuthGate
  /// renvoie alors vers l'écran de connexion).
  Future<bool> deleteAccount({required String currentPassword}) {
    return _run(() => _service.deleteAccount(currentPassword: currentPassword));
  }

  /// Met à jour le profil puis rafraîchit l'utilisateur courant.
  Future<bool> updateProfile({
    required String firstName,
    required String lastName,
    String? phoneNumber,
    DateTime? birthDate,
    GeoArea? homeLocation,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        birthDate: birthDate,
        homeLocation: homeLocation,
      );
      final user = _service.currentUser;
      if (user != null) {
        _profile = await _service.fetchProfile(user.uid);
        // Resync du device : la nouvelle résidence + la position GPS éventuelle
        // mettent à jour le ciblage de la Cloud Function de notifs.
        unawaited(
          _notifications.registerForUser(
            userId: user.uid,
            homeLocation: _profile?.homeLocation ?? const GeoArea(),
          ),
        );
      }
      return true;
    } catch (_) {
      _error = AppError.profileUpdateFailed;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AccountDisabledException {
      _error = AppError.accountDisabled;
      return false;
    } on FirebaseAuthException catch (e) {
      _error = _codeFor(e);
      return false;
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'auth action');
      _error = AppError.generic;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  AppError _codeFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return AppError.invalidEmail;
      case 'user-disabled':
        return AppError.accountDisabled;
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return AppError.wrongCredentials;
      case 'email-already-in-use':
        return AppError.emailInUse;
      case 'username-already-in-use':
        return AppError.usernameInUse;
      case 'weak-password':
        return AppError.weakPassword;
      case 'requires-recent-login':
        return AppError.requiresRecentLogin;
      case 'network-request-failed':
        return AppError.networkRequestFailed;
      default:
        return AppError.authFailed;
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
