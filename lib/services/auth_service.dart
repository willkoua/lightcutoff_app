import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../models/enums.dart';

/// Levée lorsqu'un compte désactivé tente de se connecter.
class AccountDisabledException implements Exception {
  const AccountDisabledException();
}

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Future<AppUser?> fetchProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromDoc(doc);
  }

  Future<void> signIn({required String email, required String password}) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final profile = await fetchProfile(cred.user!.uid);
    if (profile != null && profile.isDisabled) {
      await _auth.signOut();
      throw const AccountDisabledException();
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    String? phoneNumber,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;
    await cred.user!.updateDisplayName(displayName.trim());

    final user = AppUser(
      uid: uid,
      email: email.trim(),
      displayName: displayName.trim(),
      phoneNumber: phoneNumber?.trim(),
      role: UserRole.citizen,
      status: AccountStatus.active,
    );
    await _users.doc(uid).set(user.toCreateMap());

    await cred.user!.sendEmailVerification();
  }

  Future<void> sendEmailVerification() =>
      _auth.currentUser?.sendEmailVerification() ?? Future.value();

  /// Recharge l'utilisateur courant pour rafraîchir `emailVerified`.
  Future<void> reloadUser() => _auth.currentUser?.reload() ?? Future.value();

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  Future<void> signOut() => _auth.signOut();
}
