import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/geo.dart';
import '../repositories/auth_repository.dart';

/// Implémentation Firebase de [AuthRepository].
class AuthService implements AuthRepository {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  @override
  User? get currentUser => _auth.currentUser;
  @override
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _usernamesRef =>
      _firestore.collection('usernames');

  String _normUsername(String u) => u.trim().toLowerCase();

  @override
  Future<AppUser?> fetchProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromDoc(doc);
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    final doc = await _usernamesRef.doc(_normUsername(username)).get();
    return !doc.exists;
  }

  @override
  Future<void> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final id = identifier.trim();
    String email = id;
    if (!id.contains('@')) {
      // Pseudo → email via l'index public.
      final doc = await _usernamesRef.doc(_normUsername(id)).get();
      final mapped = doc.data()?['email'] as String?;
      if (mapped == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }
      email = mapped;
    }
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _syncEmailIndex(cred.user!);
    final profile = await fetchProfile(cred.user!.uid);
    if (profile != null && profile.isDisabled) {
      await _auth.signOut();
      throw const AccountDisabledException();
    }
  }

  /// Resynchronise l'email (doc user + index) si l'email Auth a changé
  /// (ex. après confirmation d'un changement d'email).
  Future<void> _syncEmailIndex(User user) async {
    final authEmail = user.email;
    if (authEmail == null) return;
    final profile = await fetchProfile(user.uid);
    if (profile == null || profile.email == authEmail) return;
    final batch = _firestore.batch();
    batch.update(_users.doc(user.uid), {
      'email': authEmail,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (profile.username.isNotEmpty) {
      batch.set(_usernamesRef.doc(_normUsername(profile.username)), {
        'uid': user.uid,
        'email': authEmail,
      });
    }
    await batch.commit();
  }

  @override
  Future<void> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? phoneNumber,
    DateTime? birthDate,
  }) async {
    final uname = _normUsername(username);
    // Disponibilité du pseudo (meilleur effort avant la création du compte).
    if (!await isUsernameAvailable(uname)) {
      throw FirebaseAuthException(code: 'username-already-in-use');
    }
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user!.uid;

    final appUser = AppUser(
      uid: uid,
      email: email.trim(),
      username: uname,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      birthDate: birthDate,
      phoneNumber: phoneNumber?.trim(),
      role: UserRole.citizen,
      status: AccountStatus.active,
    );
    await cred.user!.updateDisplayName(appUser.fullName);

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), appUser.toCreateMap());
    batch.set(_usernamesRef.doc(uname), {'uid': uid, 'email': email.trim()});
    await batch.commit();

    await cred.user!.sendEmailVerification();
  }

  @override
  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    String? phoneNumber,
    DateTime? birthDate,
    GeoArea? homeLocation,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
    await user.updateDisplayName(fullName);
    await _users.doc(user.uid).update({
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate) : null,
      'phoneNumber': phoneNumber?.trim(),
      'homeLocation': (homeLocation ?? const GeoArea()).toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setQuartierFollowed({
    required String uid,
    required String key,
    required bool followed,
  }) async {
    await _users.doc(uid).update({
      'followedQuartiers':
          followed
              ? FieldValue.arrayUnion([key])
              : FieldValue.arrayRemove([key]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _reauthenticate(user, currentPassword);
    // Envoie un lien à la nouvelle adresse ; l'email Auth ne change qu'après
    // confirmation. La resynchro users/index a lieu à la prochaine connexion.
    await user.verifyBeforeUpdateEmail(newEmail.trim());
  }

  @override
  Future<void> changePassword({
    required String newPassword,
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _reauthenticate(user, currentPassword);
    await user.updatePassword(newPassword);
  }

  @override
  Future<void> deleteAccount({required String currentPassword}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    // Sécurité : on exige le mot de passe (action sensible et définitive).
    await _reauthenticate(user, currentPassword);
    // Nettoyage serveur (anonymisation des signalements + suppression
    // profil/devices/médias/compte Auth) via la Cloud Function callable.
    await FirebaseFunctions.instance.httpsCallable('deleteAccount').call();
    // Le compte Auth est supprimé côté serveur ; on purge la session locale.
    await _auth.signOut();
  }

  Future<void> _reauthenticate(User user, String currentPassword) async {
    final email = user.email;
    if (email == null) throw FirebaseAuthException(code: 'invalid-credential');
    final cred = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(cred);
  }

  @override
  Future<void> sendEmailVerification() =>
      _auth.currentUser?.sendEmailVerification() ?? Future.value();
  @override
  Future<void> reloadUser() => _auth.currentUser?.reload() ?? Future.value();

  @override
  Future<void> signOut() => _auth.signOut();
}
