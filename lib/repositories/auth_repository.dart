import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../models/geo.dart';

/// Levée lorsqu'un compte désactivé tente de se connecter.
class AccountDisabledException implements Exception {
  const AccountDisabledException();
}

/// Levée lorsqu'un utilisateur annule une connexion sociale (ferme la
/// pop-up Google) — à traiter silencieusement côté UI.
class SocialSignInCancelledException implements Exception {
  const SocialSignInCancelledException();
}

/// Contrat d'accès à l'authentification et au profil utilisateur.
/// L'implémentation concrète (Firebase) est interchangeable.
abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  User? get currentUser;
  bool get isEmailVerified;

  Future<AppUser?> fetchProfile(String uid);

  /// `true` si le pseudo (normalisé en minuscules) n'est pas déjà pris.
  Future<bool> isUsernameAvailable(String username);

  /// Connexion par **pseudo OU email** + mot de passe.
  Future<void> signInWithIdentifier({
    required String identifier,
    required String password,
  });

  /// Connexion **Google** (Sign in with Google) → credential Firebase.
  /// Lève [SocialSignInCancelledException] si l'utilisateur annule. Le profil
  /// (`users`/`usernames`) n'est PAS créé ici : un compte social sans profil
  /// est routé vers l'écran « compléter le profil » (cf. [completeSocialProfile]).
  Future<void> signInWithGoogle();

  /// `true` si l'utilisateur connecté n'a pas encore de profil Firestore
  /// (cas d'un 1er login social) — il doit alors compléter son profil.
  Future<bool> needsProfile();

  /// Crée le profil (`users` + `usernames`) d'un compte social déjà
  /// authentifié, après que l'utilisateur a choisi un pseudo unique. Symétrique
  /// à [register] mais sans création de compte Auth ni email de vérification.
  Future<void> completeSocialProfile({
    required String firstName,
    required String lastName,
    required String username,
    String? phoneNumber,
    DateTime? birthDate,
  });

  Future<void> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? phoneNumber,
    DateTime? birthDate,
  });

  Future<void> sendEmailVerification();
  Future<void> reloadUser();

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    String? phoneNumber,
    DateTime? birthDate,
    GeoArea? homeLocation,
  });

  /// Suit / ne suit plus un quartier (pour les alertes de coupures planifiées).
  /// `key` = clé normalisée `REGION|VILLE|QUARTIER` (`OfficialOutage.followKey`).
  Future<void> setQuartierFollowed({
    required String uid,
    required String key,
    required bool followed,
  });

  /// Change l'email (ré-authentification + email de confirmation à la nouvelle
  /// adresse ; l'email effectif change après que l'utilisateur clique le lien).
  Future<void> changeEmail({
    required String newEmail,
    required String currentPassword,
  });

  Future<void> changePassword({
    required String newPassword,
    required String currentPassword,
  });

  /// Suppression définitive du compte (RGPD / exigence stores). Ré-authentifie
  /// avec [currentPassword], déclenche le nettoyage serveur (Cloud Function
  /// `deleteAccount` : anonymise les signalements, supprime profil/devices/
  /// médias/compte Auth), puis déconnecte.
  Future<void> deleteAccount({required String currentPassword});

  Future<void> signOut();
}
