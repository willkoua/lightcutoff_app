import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/geo.dart';
import '../repositories/auth_repository.dart';
import '../services/auth_service.dart';

enum AuthStatus {
  unknown,
  authenticated,
  awaitingVerification,
  unauthenticated,
}

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repository})
    : _service = repository ?? AuthService() {
    _sub = _service.authStateChanges.listen(_onAuthStateChanged);
  }

  final AuthRepository _service;
  late final StreamSubscription<User?> _sub;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _profile;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  AppUser? get profile => _profile;
  bool get busy => _busy;
  String? get error => _error;

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      _profile = null;
      _status = AuthStatus.unauthenticated;
    } else if (!user.emailVerified) {
      _profile = null;
      _status = AuthStatus.awaitingVerification;
    } else {
      _profile = await _service.fetchProfile(user.uid);
      _status = AuthStatus.authenticated;
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

  Future<bool> login({required String email, required String password}) {
    return _run(() => _service.signIn(email: email, password: password));
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
    String? phoneNumber,
  }) {
    return _run(
      () => _service.register(
        email: email,
        password: password,
        displayName: displayName,
        phoneNumber: phoneNumber,
      ),
    );
  }

  Future<void> logout() => _service.signOut();

  /// Met à jour le profil puis rafraîchit l'utilisateur courant.
  Future<bool> updateProfile({
    required String displayName,
    String? phoneNumber,
    GeoArea? homeLocation,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.updateProfile(
        displayName: displayName,
        phoneNumber: phoneNumber,
        homeLocation: homeLocation,
      );
      final user = _service.currentUser;
      if (user != null) _profile = await _service.fetchProfile(user.uid);
      return true;
    } catch (_) {
      _error = 'Échec de la mise à jour du profil.';
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
      _error = 'Ce compte a été désactivé.';
      return false;
    } on FirebaseAuthException catch (e) {
      _error = _messageFor(e);
      return false;
    } catch (_) {
      _error = 'Une erreur est survenue. Réessayez.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Email invalide.';
      case 'user-disabled':
        return 'Ce compte a été désactivé.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email ou mot de passe incorrect.';
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé.';
      case 'weak-password':
        return 'Mot de passe trop faible.';
      case 'network-request-failed':
        return 'Pas de connexion réseau.';
      default:
        return 'Échec de l\'authentification.';
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
