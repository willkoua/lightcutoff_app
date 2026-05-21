import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../models/geo.dart';

/// Levée lorsqu'un compte désactivé tente de se connecter.
class AccountDisabledException implements Exception {
  const AccountDisabledException();
}

/// Contrat d'accès à l'authentification et au profil utilisateur.
/// L'implémentation concrète (Firebase) est interchangeable.
abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  User? get currentUser;
  bool get isEmailVerified;

  Future<AppUser?> fetchProfile(String uid);

  Future<void> signIn({required String email, required String password});

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    String? phoneNumber,
  });

  Future<void> sendEmailVerification();
  Future<void> reloadUser();

  Future<void> updateProfile({
    required String displayName,
    String? phoneNumber,
    GeoArea? homeLocation,
  });

  Future<void> signOut();
}
