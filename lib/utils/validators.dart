import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

// Regex partagées par les validators — privées au fichier.
final _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
final _usernameRegex = RegExp(r'^[a-z0-9_.]+$');

/// Validateurs de formulaires localisés. Utilisation :
///   `validator: AppLocalizations.of(context).validateEmail`
///
/// Pour les champs `required` avec un libellé personnalisé :
///   `validator: (v) => l.validateRequired(v, label: l.registerFirstNameRequired)`
extension Validators on AppLocalizations {
  String? validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return validatorEmailRequired;
    if (!_emailRegex.hasMatch(v)) return validatorEmailInvalid;
    return null;
  }

  String? validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return validatorPasswordRequired;
    if (v.length < 6) return validatorPasswordTooShort;
    return null;
  }

  String? validateRequired(String? value, {String? label}) {
    if ((value?.trim() ?? '').isEmpty) {
      return validatorRequired(label ?? validatorRequiredFieldFallback);
    }
    return null;
  }

  /// Pseudo : 3-20 caractères, minuscules/chiffres/_/. (normalisé en minuscules).
  String? validateUsername(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return validatorUsernameRequired;
    if (v.length < 3) return validatorUsernameTooShort;
    if (v.length > 20) return validatorUsernameTooLong;
    if (!_usernameRegex.hasMatch(v)) return validatorUsernameInvalid;
    return null;
  }

  /// Identifiant de connexion : pseudo OU email (non vide).
  String? validateIdentifier(String? value) {
    if ((value?.trim() ?? '').isEmpty) return validatorIdentifierRequired;
    return null;
  }

  String? validatePhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return validatorPhoneRequired;
    if (v.replaceAll(RegExp(r'[\s+]'), '').length < 8) {
      return validatorPhoneInvalid;
    }
    return null;
  }
}
