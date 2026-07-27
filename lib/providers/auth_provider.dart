import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_error.dart';
import '../models/app_user.dart';
import '../models/geo.dart';
import '../repositories/auth_repository.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../utils/crash_reporter.dart';

enum AuthStatus {
  unknown,

  /// Session **Firebase Anonymous Auth** (uid présent, sans email/profil).
  /// L'utilisateur peut signaler et voter ; les fonctions sociales (profil,
  /// stats, notifs, suivi quartier) sont gardées derrière un mur d'upgrade.
  anonymous,

  authenticated,
  awaitingVerification,

  /// Authentifié (email vérifié) mais **sans profil Firestore** : cas d'un 1er
  /// login social (Google) → l'utilisateur doit choisir un pseudo et compléter
  /// son profil avant d'entrer dans l'app.
  profileIncomplete,

  /// Aucune session active **et** la tentative de signInAnonymously a échoué
  /// (souvent : hors-ligne, ou Anonymous Auth non activé côté console). L'UI
  /// affiche un écran « Réessayer », ne re-tente PAS automatiquement (évite la
  /// boucle). Le bouton « J'ai déjà un compte » reste accessible.
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

  /// Vrai si une tentative d'auto-`signInAnonymously` a déjà été lancée pendant
  /// cette session de provider. Garde-fou anti-boucle : on ne retente pas
  /// automatiquement après un échec — c'est à l'UI (écran « Réessayer »)
  /// d'appeler [retryAnonymousSignIn].
  bool _anonymousSignInAttempted = false;

  /// Vrai si l'event analytics `anonymous_started` a déjà été émis pour la
  /// session courante. Évite les doublons quand le listener d'auth re-fire sur
  /// la même session anonyme (rotation de token, reload, etc.).
  bool _anonymousStartedLogged = false;

  AuthStatus get status => _status;
  AppUser? get profile => _profile;
  bool get busy => _busy;
  AppError? get error => _error;

  /// `true` si la session courante est anonyme (Firebase Anonymous Auth).
  bool get isAnonymous => _service.isAnonymous;

  Future<void> _onAuthStateChanged(User? user) async {
    // Toute session vivante RÉARME la reconnexion anonyme automatique : si la
    // session meurt plus tard (ex. compte supprimé côté serveur → refresh de
    // jeton refusé → authStateChanges émet null), on retentera une session
    // anonyme au lieu de rester bloqué sur « Réessayer » (résilience
    // 2026-07-26 — découvert en purgant les comptes de test prod).
    if (user != null) _anonymousSignInAttempted = false;

    CrashReporter.setUser(user?.uid);
    if (user == null) {
      _profile = null;
      // Désinscription du device pour ne plus recevoir de notifs.
      unawaited(_notifications.unregister());
      // Première arrivée sans session → on tente une session anonyme
      // transparente. Le listener sera rappelé avec le User anonyme.
      //
      // On NE force PAS `_status = unknown` ici : au démarrage à froid le statut
      // est déjà `unknown` (défaut → SplashScreen, ce qu'on veut). Après une
      // **déconnexion**, le statut courant est `authenticated`/`anonymous`
      // (MainShell) ; le laisser tel quel pendant la brève re-connexion anonyme
      // évite un flash de SplashScreen — la transition est ainsi vraiment
      // transparente, comme prévu.
      if (!_anonymousSignInAttempted) {
        _anonymousSignInAttempted = true;
        try {
          await _service.signInAnonymously();
          // Pas de notifyListeners ici : le listener re-fire avec le User.
          return;
        } catch (e, st) {
          CrashReporter.recordError(e, st, reason: 'anonymous sign-in');
          _status = AuthStatus.unauthenticated;
          _error = AppError.networkRequestFailed;
        }
      } else {
        // Échec déjà passé OU déconnexion explicite : on reste en
        // unauthenticated, l'UI affiche « Réessayer ».
        _status = AuthStatus.unauthenticated;
      }
    } else if (user.isAnonymous) {
      // Session anonyme : pas de profil, pas de device notifs. L'utilisateur
      // peut signaler et voter ; les fonctions sociales sont gardées par un
      // mur d'upgrade dans l'UI.
      _profile = null;
      _status = AuthStatus.anonymous;
      // Analytics : dénominateur du funnel de conversion. Une seule fois par
      // session de provider (réarmé par logout).
      if (!_anonymousStartedLogged) {
        _anonymousStartedLogged = true;
        unawaited(AnalyticsService.instance.logAnonymousStarted());
      }
    } else if (_needsEmailVerification(user)) {
      _profile = null;
      _status = AuthStatus.awaitingVerification;
    } else {
      // Email vérifié : on charge le profil. Absent (1er login social) →
      // **création automatique** avec pseudo généré (`prenom_NNN`, zéro
      // friction — décision 2026-07-25), personnalisable une fois ensuite.
      // Si la création échoue (réseau…), repli sur l'écran de complétion
      // manuelle (profileIncomplete). En cas d'erreur réseau de lecture, on ne
      // bloque pas un utilisateur existant.
      try {
        var profile = await _service.fetchProfile(user.uid);
        if (profile == null) {
          try {
            final generated = await _service.autoCreateSocialProfile();
            _justGeneratedUsername = generated;
            profile = await _service.fetchProfile(user.uid);
            AnalyticsService.instance.logSignUp();
          } catch (_) {
            // Repli : l'écran « Compléter mon profil » reste la sortie de
            // secours si la génération échoue.
          }
        }
        _profile = profile;
        if (profile == null) {
          _status = AuthStatus.profileIncomplete;
        } else {
          _status = AuthStatus.authenticated;
          // Device pour les notifs push (idempotent, ne bloque pas).
          unawaited(
            _notifications.registerForUser(
              userId: user.uid,
              homeLocation: profile.homeLocation,
            ),
          );
        }
      } catch (_) {
        _status = AuthStatus.authenticated;
      }
    }
    notifyListeners();
  }

  /// Pseudo fraîchement généré lors d'une création automatique de profil
  /// social — à annoncer UNE fois à l'utilisateur (« Ton pseudo : X,
  /// modifiable une fois dans ton profil »). Consommé par [MainShell].
  String? _justGeneratedUsername;
  String? takeGeneratedUsernameAnnouncement() {
    final u = _justGeneratedUsername;
    _justGeneratedUsername = null;
    return u;
  }

  /// Change le pseudo — une seule fois à vie. Recharge le profil en cas de
  /// succès. Lève tel quel les erreurs (`username-already-in-use`,
  /// `username-change-exhausted`) pour un message UI précis.
  Future<bool> changeUsername(String newUsername) async {
    final ok = await _run(() => _service.changeUsername(newUsername));
    if (ok) {
      final user = _service.currentUser;
      if (user != null) _profile = await _service.fetchProfile(user.uid);
      notifyListeners();
    }
    return ok;
  }

  /// La vérification d'email ne concerne QUE le fournisseur `password`
  /// (inscription par e-mail). Les connexions sociales (Facebook, Apple,
  /// Google) sont validées par leur fournisseur — or Firebase marque les
  /// emails Facebook/Apple comme non vérifiés, ce qui envoyait à tort ces
  /// utilisateurs sur l'écran « Vérifie ton email » (bug corrigé 2026-07-25).
  static bool _needsEmailVerification(User user) {
    final hasPasswordProvider = user.providerData.any(
      (p) => p.providerId == 'password',
    );
    return hasPasswordProvider && !user.emailVerified;
  }

  /// Re-tente une session anonyme après un échec initial (bouton « Réessayer »
  /// de l'écran [AuthStatus.unauthenticated]). Réinitialise le garde-fou et
  /// rejoue le chemin standard via le listener.
  Future<bool> retryAnonymousSignIn() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _anonymousSignInAttempted = true;
      await _service.signInAnonymously();
      // Le listener `_onAuthStateChanged` posera le statut final ;
      // on ne touche pas _status ici.
      return true;
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'anonymous sign-in retry');
      _error = AppError.networkRequestFailed;
      _status = AuthStatus.unauthenticated;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String? get pendingEmail => _service.currentUser?.email;

  /// Nom affiché du compte courant (ex. fourni par Google) — sert à préremplir
  /// l'écran « compléter le profil » d'un 1er login social.
  String? get pendingDisplayName => _service.currentUser?.displayName;

  Future<void> resendVerificationEmail() => _service.sendEmailVerification();

  /// Demande un mail de réinitialisation de mot de passe. UI : toujours
  /// présenter un message générique de succès (pas de leak de l'existence
  /// du compte). Retourne `true` si le service n'a rien levé, `false` sur
  /// erreur réelle (format email invalide, réseau coupé…).
  Future<bool> requestPasswordReset({required String identifier}) {
    return _run(() => _service.sendPasswordResetEmail(identifier: identifier));
  }

  /// Recharge l'utilisateur ; si l'email est vérifié, bascule sur authenticated.
  /// Sert à la fois au flow `register` classique et à l'upgrade post-anonyme :
  /// dans les deux cas, le device n'avait PAS été enregistré jusqu'ici (anonyme
  /// → bloqué par règles ; authentifié non vérifié → pas registerForUser). On
  /// l'enregistre maintenant pour activer les notifs sans attendre un
  /// redémarrage de l'app.
  Future<bool> refreshVerification() async {
    await _service.reloadUser();
    final user = _service.currentUser;
    if (user != null && user.emailVerified) {
      final profile = await _service.fetchProfile(user.uid);
      _profile = profile;
      _status = AuthStatus.authenticated;
      notifyListeners();
      if (profile != null) {
        unawaited(
          _notifications.registerForUser(
            userId: user.uid,
            homeLocation: profile.homeLocation,
          ),
        );
      }
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
  }) async {
    final ok = await _run(
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
    if (ok) AnalyticsService.instance.logSignUp();
    return ok;
  }

  /// Upgrade d'une session anonyme vers un compte email/mot de passe : préserve
  /// l'uid (donc l'historique reports/votes anonymes), crée le profil + pseudo,
  /// envoie le mail de vérification → bascule en [AuthStatus.awaitingVerification].
  ///
  /// Note : `linkWithCredential` ne déclenche pas toujours `authStateChanges`
  /// (l'uid ne change pas — ce n'est pas un sign-in event au sens Firebase).
  /// On rejoue donc explicitement le routage avec le user courant pour passer
  /// de `anonymous` à `awaitingVerification`.
  Future<bool> upgradeWithEmail({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? phoneNumber,
    DateTime? birthDate,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.upgradeAnonymous(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        username: username,
        phoneNumber: phoneNumber,
        birthDate: birthDate,
      );
      AnalyticsService.instance.logSignUp();
      // Marqueur funnel dédié : permet de distinguer un upgrade post-anonyme
      // d'un `register` direct (différentes audiences, différents KPIs).
      unawaited(AnalyticsService.instance.logUpgradeCompleted());
      await _onAuthStateChanged(_service.currentUser);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _codeFor(e);
      return false;
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'upgrade anonymous');
      _error = AppError.authFailed;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Connexion **Google**. Au succès, le listener d'auth bascule vers
  /// `profileIncomplete` (1er login → choisir un pseudo) ou `authenticated`.
  /// Une annulation par l'utilisateur est silencieuse (pas de message d'erreur).
  Future<bool> signInWithGoogle() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.signInWithGoogle();
      // Si la connexion a LIÉ le compte social à la session anonyme (même
      // uid, historique préservé), authStateChanges ne re-fire pas toujours —
      // on rejoue l'aiguillage manuellement (même précaution que
      // upgradeWithEmail).
      await _onAuthStateChanged(_service.currentUser);
      return true;
    } on SocialSignInCancelledException {
      return false; // annulation : aucun message
    } on AccountDisabledException {
      _error = AppError.accountDisabled;
      return false;
    } on FirebaseAuthException catch (e) {
      _error = _codeFor(e);
      return false;
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'google sign-in');
      _error = AppError.socialSignInFailed;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithFacebook() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.signInWithFacebook();
      // Si la connexion a LIÉ le compte social à la session anonyme (même
      // uid, historique préservé), authStateChanges ne re-fire pas toujours —
      // on rejoue l'aiguillage manuellement (même précaution que
      // upgradeWithEmail).
      await _onAuthStateChanged(_service.currentUser);
      return true;
    } on SocialSignInCancelledException {
      return false; // annulation : aucun message
    } on AccountDisabledException {
      _error = AppError.accountDisabled;
      return false;
    } on FirebaseAuthException catch (e) {
      _error = _codeFor(e);
      return false;
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'facebook sign-in');
      _error = AppError.socialSignInFailed;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithApple() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _service.signInWithApple();
      // Si la connexion a LIÉ le compte social à la session anonyme (même
      // uid, historique préservé), authStateChanges ne re-fire pas toujours —
      // on rejoue l'aiguillage manuellement (même précaution que
      // upgradeWithEmail).
      await _onAuthStateChanged(_service.currentUser);
      return true;
    } on SocialSignInCancelledException {
      return false; // annulation : aucun message
    } on AccountDisabledException {
      _error = AppError.accountDisabled;
      return false;
    } on FirebaseAuthException catch (e) {
      _error = _codeFor(e);
      return false;
    } catch (e, st) {
      CrashReporter.recordError(e, st, reason: 'apple sign-in');
      _error = AppError.socialSignInFailed;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Finalise le profil d'un compte social (pseudo unique + infos), crée les
  /// docs `users`/`usernames`, puis bascule en `authenticated`.
  Future<bool> completeProfile({
    required String firstName,
    required String lastName,
    required String username,
    String? phoneNumber,
    DateTime? birthDate,
  }) async {
    final ok = await _run(
      () => _service.completeSocialProfile(
        firstName: firstName,
        lastName: lastName,
        username: username,
        phoneNumber: phoneNumber,
        birthDate: birthDate,
      ),
    );
    if (ok) {
      AnalyticsService.instance.logSignUp();
      final user = _service.currentUser;
      if (user != null) {
        _profile = await _service.fetchProfile(user.uid);
        _status = AuthStatus.authenticated;
        unawaited(
          _notifications.registerForUser(
            userId: user.uid,
            homeLocation: _profile?.homeLocation ?? const GeoArea(),
          ),
        );
        notifyListeners();
      }
    }
    return ok;
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

  /// Déconnecte la session courante. Pour une session anonyme : équivaut à
  /// « effacer cette session » (un nouvel anonyme sera créé automatiquement
  /// au prochain démarrage). Pour un compte réel : retour à l'anonyme aussi.
  /// On RÉARME `_anonymousSignInAttempted` pour autoriser la nouvelle
  /// tentative anonyme via le listener.
  Future<void> logout() async {
    _anonymousSignInAttempted = false;
    // Si l'utilisateur s'efface puis revient en anonyme, c'est une **nouvelle**
    // session côté analytics → on rejoue logAnonymousStarted.
    _anonymousStartedLogged = false;
    // Désinscription du device AVANT signOut : la suppression de
    // `devices/{token}` exige d'être encore le propriétaire (règle
    // `isOwner(userId)`). Après signOut, la requête partirait sans auth (ou en
    // anonyme) → rejetée en silence, le doc survivrait et le téléphone
    // continuerait de recevoir des notifs de compte. L'appel du listener
    // (`_onAuthStateChanged(null)`) reste en filet best-effort.
    try {
      await _notifications.unregister();
    } catch (_) {
      // Best-effort : la déconnexion ne doit jamais être bloquée par FCM.
    }
    await _service.signOut();
  }

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

  /// Vrai si l'utilisateur suit ce quartier (clé `REGION|VILLE|QUARTIER`).
  bool isFollowingQuartier(String key) =>
      _profile?.followedQuartiers.contains(key) ?? false;

  /// Suit / ne suit plus un quartier (alertes coupures planifiées) puis
  /// rafraîchit le profil local.
  Future<void> toggleFollowQuartier(String key) async {
    final uid = _service.currentUser?.uid;
    if (uid == null) return;
    final following = isFollowingQuartier(key);
    await _service.setQuartierFollowed(
      uid: uid,
      key: key,
      followed: !following,
    );
    _profile = await _service.fetchProfile(uid);
    AnalyticsService.instance.logQuartierFollowed(following: !following);
    notifyListeners();
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
      case 'account-exists-with-different-credential':
        return AppError.accountExistsDifferentCredential;
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
