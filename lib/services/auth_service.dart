import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/geo.dart';
import '../repositories/auth_repository.dart';
import '../utils/username_generator.dart';

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
  @override
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

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

  /// Connexion sociale AVEC PRÉSERVATION de l'historique anonyme
  /// (décision 2026-07-26) : si la session courante est anonyme, on tente de
  /// LIER le credential social à l'uid courant (`linkWithCredential`) — les
  /// signalements/votes anonymes restent attachés. Si ce compte social est
  /// déjà rattaché à un autre utilisateur NJUKA (vrai « j'ai déjà un
  /// compte »), la liaison échoue → repli sur la connexion classique
  /// (changement d'uid, perte d'historique inévitable et légitime).
  /// Nom affiché fourni par le provider social (additionalUserInfo). Utile
  /// surtout après un LINK : Firebase ne copie pas le nom du provider sur le
  /// User existant — sans ça, le profil auto-créé partirait de l'email.
  static String? _displayNameFromCredential(UserCredential cred) {
    final p = cred.additionalUserInfo?.profile;
    if (p == null) return null;
    final direct = (p['name'] ?? p['displayName']) as String?;
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final given = p['given_name'] ?? p['first_name'];
    final family = p['family_name'] ?? p['last_name'];
    final full =
        [given, family].whereType<String>().join(' ').trim();
    return full.isEmpty ? null : full;
  }

  /// Complète le displayName du User s'il est vide, à partir des infos du
  /// provider — le profil auto-créé (noms + germe du pseudo) en dépend.
  Future<void> _ensureDisplayName(UserCredential cred) async {
    final user = cred.user;
    if (user == null) return;
    if ((user.displayName ?? '').trim().isNotEmpty) return;
    final name = _displayNameFromCredential(cred);
    if (name == null) return;
    try {
      await user.updateDisplayName(name);
      await user.reload();
    } catch (_) {
      // Cosmétique : ne bloque jamais la connexion.
    }
  }

  Future<UserCredential> _signInOrLink(AuthCredential credential) async {
    final current = _auth.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        final cred = await current.linkWithCredential(credential);
        // Le prochain commit Firestore doit porter le nouveau
        // `sign_in_provider` (sinon PERMISSION_DENIED sur la création de
        // profil avec un token encore « anonymous ») — même précaution que
        // upgradeAnonymous.
        await cred.user!.getIdToken(true);
        return cred;
      } on FirebaseAuthException catch (e) {
        const fallbackCodes = {
          'credential-already-in-use',
          'email-already-in-use',
          'account-exists-with-different-credential',
        };
        if (!fallbackCodes.contains(e.code)) rethrow;
      }
    }
    return _auth.signInWithCredential(credential);
  }

  @override
  Future<void> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      // L'utilisateur a fermé la pop-up de sélection de compte.
      throw const SocialSignInCancelledException();
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final cred = await _signInOrLink(credential);
    await _ensureDisplayName(cred);
    // Compte désactivé ? (le profil peut déjà exister si réinscription)
    final profile = await fetchProfile(cred.user!.uid);
    if (profile != null && profile.isDisabled) {
      await GoogleSignIn().signOut();
      await _auth.signOut();
      throw const AccountDisabledException();
    }
  }

  /// Connexion via Facebook : ouvre le SDK Facebook, échange l'access token
  /// contre un credential Firebase. Symétrique à [signInWithGoogle].
  @override
  Future<void> signInWithFacebook() async {
    final result = await FacebookAuth.instance.login(
      permissions: const ['email', 'public_profile'],
    );
    if (result.status == LoginStatus.cancelled) {
      throw const SocialSignInCancelledException();
    }
    final token = result.accessToken;
    if (result.status != LoginStatus.success || token == null) {
      throw FirebaseAuthException(code: 'facebook-login-failed');
    }
    final credential = FacebookAuthProvider.credential(token.tokenString);
    final cred = await _signInOrLink(credential);
    await _ensureDisplayName(cred);
    final profile = await fetchProfile(cred.user!.uid);
    if (profile != null && profile.isDisabled) {
      await FacebookAuth.instance.logOut();
      await _auth.signOut();
      throw const AccountDisabledException();
    }
  }

  /// Connexion avec Apple (obligatoire sur l'App Store dès qu'une connexion
  /// tierce est proposée — règle 4.8). Utilise le flux natif de firebase_auth
  /// ([signInWithProvider]) : pas de plugin supplémentaire. ⚠️ Apple ne
  /// transmet nom/email qu'à la PREMIÈRE autorisation — le flux
  /// `CompleteProfileScreen` (profileIncomplete) couvre les infos manquantes.
  @override
  Future<void> signInWithApple() async {
    final provider =
        AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
    try {
      UserCredential cred;
      final current = _auth.currentUser;
      if (current != null && current.isAnonymous) {
        // Préservation de l'historique anonyme, comme _signInOrLink.
        try {
          cred = await current.linkWithProvider(provider);
          await cred.user!.getIdToken(true);
        } on FirebaseAuthException catch (e) {
          const fallbackCodes = {
            'credential-already-in-use',
            'email-already-in-use',
            'account-exists-with-different-credential',
          };
          if (!fallbackCodes.contains(e.code)) rethrow;
          cred = await _auth.signInWithProvider(provider);
        }
      } else {
        cred = await _auth.signInWithProvider(provider);
      }
      await _ensureDisplayName(cred);
      final profile = await fetchProfile(cred.user!.uid);
      if (profile != null && profile.isDisabled) {
        await _auth.signOut();
        throw const AccountDisabledException();
      }
    } on FirebaseAuthException catch (e) {
      // Annulation utilisateur (fermeture de la feuille Apple) → même
      // exception douce que Google/Facebook, pas une erreur.
      if (e.code == 'canceled' || e.code == 'web-context-canceled') {
        throw const SocialSignInCancelledException();
      }
      rethrow;
    }
  }

  @override
  Future<bool> needsProfile() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    return (await fetchProfile(user.uid)) == null;
  }

  @override
  Future<void> completeSocialProfile({
    required String firstName,
    required String lastName,
    required String username,
    String? phoneNumber,
    DateTime? birthDate,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final uname = _normUsername(username);
    if (!await isUsernameAvailable(uname)) {
      throw FirebaseAuthException(code: 'username-already-in-use');
    }
    final email = user.email ?? '';
    final appUser = AppUser(
      uid: user.uid,
      email: email,
      username: uname,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      birthDate: birthDate,
      phoneNumber: phoneNumber?.trim(),
      photoURL: user.photoURL,
      role: UserRole.citizen,
      status: AccountStatus.active,
    );
    await user.updateDisplayName(appUser.fullName);
    final batch = _firestore.batch();
    batch.set(_users.doc(user.uid), appUser.toCreateMap());
    batch.set(_usernamesRef.doc(uname), {'uid': user.uid, 'email': email});
    await batch.commit();
  }

  /// Crée automatiquement le profil d'un compte social avec un **pseudo
  /// généré** (`prenom_NNN`) — zéro friction au 1er login, personnalisable une
  /// fois ensuite (cf. [changeUsername]). Réessaie avec un autre suffixe en
  /// cas de collision. Renvoie le pseudo attribué.
  @override
  Future<String> autoCreateSocialProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final display = (user.displayName ?? '').trim();
    final parts = display.split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final seed = display.isNotEmpty ? display : user.email;

    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      final candidate = _normUsername(generateUsername(seed));
      try {
        await completeSocialProfile(
          firstName: firstName,
          lastName: lastName,
          username: candidate,
        );
        return candidate;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'username-already-in-use') rethrow;
        lastError = e; // collision improbable → nouveau suffixe
      }
    }
    throw lastError ?? FirebaseAuthException(code: 'username-already-in-use');
  }

  /// Change le pseudo — **une seule fois, définitivement** (décision
  /// 2026-07-25 : le pseudo identifie l'utilisateur ; le compteur
  /// `usernameChangesLeft` est aussi verrouillé par les règles Firestore).
  /// L'index `usernames` est basculé atomiquement. `authorUsername` des
  /// signalements passés reste inchangé (dénormalisé immuable, voulu).
  @override
  Future<void> changeUsername(String newUsername) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final profile = await fetchProfile(user.uid);
    if (profile == null) throw FirebaseAuthException(code: 'no-profile');
    if (profile.usernameChangesLeft <= 0) {
      throw FirebaseAuthException(code: 'username-change-exhausted');
    }
    final uname = _normUsername(newUsername);
    if (uname == _normUsername(profile.username)) return;
    if (!await isUsernameAvailable(uname)) {
      throw FirebaseAuthException(code: 'username-already-in-use');
    }
    final batch = _firestore.batch();
    if (profile.username.isNotEmpty) {
      batch.delete(_usernamesRef.doc(_normUsername(profile.username)));
    }
    batch.set(_usernamesRef.doc(uname), {
      'uid': user.uid,
      'email': profile.email,
    });
    batch.update(_users.doc(user.uid), {
      'username': uname,
      'usernameChangesLeft': profile.usernameChangesLeft - 1,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
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
  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
  }

  @override
  Future<void> upgradeAnonymous({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
    String? phoneNumber,
    DateTime? birthDate,
  }) async {
    final user = _auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final uname = _normUsername(username);
    // Best-effort avant le link : si pris, on échoue tôt (le compte anonyme
    // reste intact, l'utilisateur peut réessayer avec un autre pseudo).
    if (!await isUsernameAvailable(uname)) {
      throw FirebaseAuthException(code: 'username-already-in-use');
    }
    final emailCred = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    // Link : l'uid est PRÉSERVÉ, l'historique anonyme (reports/votes) reste
    // attaché. Le sign_in_provider passe d'« anonymous » à « password » →
    // les règles Firestore autorisent à présent la création de profil/pseudo.
    final cred = await user.linkWithCredential(emailCred);
    final upgraded = cred.user!;
    // Force le rafraîchissement du token pour que le prochain commit Firestore
    // porte bien le nouveau `sign_in_provider` (sinon risque de PERMISSION_DENIED
    // sur la création de profil avec un token encore « anonymous »).
    await upgraded.getIdToken(true);

    final uid = upgraded.uid;
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
    await upgraded.updateDisplayName(appUser.fullName);

    final batch = _firestore.batch();
    batch.set(_users.doc(uid), appUser.toCreateMap());
    batch.set(_usernamesRef.doc(uname), {'uid': uid, 'email': email.trim()});
    await batch.commit();

    await upgraded.sendEmailVerification();
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
  Future<void> sendPasswordResetEmail({required String identifier}) async {
    final id = identifier.trim();
    if (id.isEmpty) {
      throw FirebaseAuthException(code: 'invalid-email');
    }
    String? email;
    if (id.contains('@')) {
      email = id;
    } else {
      // Pseudo → email via l'index public (même chemin que signInWithIdentifier).
      final doc = await _usernamesRef.doc(_normUsername(id)).get();
      email = doc.data()?['email'] as String?;
      if (email == null) {
        // Pseudo inexistant : silencieux pour ne pas révéler l'existence
        // (ou non) du compte.
        return;
      }
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      // `user-not-found` (email inconnu) : silencieux — pas de leak.
      // Autres codes (`invalid-email`, `network-request-failed`…) : on
      // propage pour mappage `AppError` côté provider.
      if (e.code == 'user-not-found') return;
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    // Déconnexion Google aussi → la prochaine connexion re-propose le sélecteur
    // de compte (sans effet si l'utilisateur n'était pas connecté via Google).
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      /* non bloquant */
    }
    await _auth.signOut();
  }
}
