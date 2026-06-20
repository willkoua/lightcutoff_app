/// Codes d'erreur **utilisateur** partagés par la couche données
/// (providers / services / repositories) — qui n'a pas de `BuildContext`.
///
/// La couche UI les traduit en messages localisés via
/// `appErrorLabel(context, code)` (voir `lib/utils/l10n_helpers.dart`).
/// Ce découplage permet aux services Firebase/OS de signaler une erreur sans
/// dépendre des `AppLocalizations`.
enum AppError {
  // --- Authentification ---
  invalidEmail,
  wrongCredentials,
  emailInUse,
  usernameInUse,
  weakPassword,
  requiresRecentLogin,
  networkRequestFailed,
  accountDisabled,
  authFailed,
  profileUpdateFailed,

  /// Connexion sociale (Google) annulée par l'utilisateur — non affichée.
  socialSignInCancelled,

  /// Échec de la connexion sociale (Google).
  socialSignInFailed,

  /// L'email est déjà lié à un compte créé avec une autre méthode.
  accountExistsDifferentCredential,

  // --- Signalements ---
  notLoggedIn,
  reportSubmitFailed,
  reportsLoadFailed,

  // --- Localisation ---
  locationServicesDisabled,
  locationPermissionDenied,
  locationNotFound,
  locationUnavailable,

  // --- Générique ---
  generic,
}
