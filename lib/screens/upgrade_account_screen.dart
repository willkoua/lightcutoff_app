import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_constants.dart';
import '../models/app_error.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';
import '../utils/l10n_helpers.dart';
import '../utils/username_generator.dart';
import '../utils/validators.dart';
import 'login_screen.dart';

/// Formulaire d'**upgrade** d'une session anonyme vers un compte email/mdp.
/// Reprend les champs de [RegisterScreen] (pseudo unique, email, mdp, tél +
/// indicatif, naissance, CGU) mais appelle `auth.upgradeWithEmail(...)` :
/// `linkWithCredential` préserve l'uid, donc tous les signalements et votes
/// déposés en anonyme restent attachés au nouvel utilisateur.
///
/// Au succès : le provider bascule en `awaitingVerification` (mail envoyé) →
/// l'AuthGate affiche `EmailVerificationScreen` automatiquement. On pop
/// simplement cet écran pour le retirer de la stack.
class UpgradeAccountScreen extends StatefulWidget {
  const UpgradeAccountScreen({super.key});

  @override
  State<UpgradeAccountScreen> createState() => _UpgradeAccountScreenState();
}

class _UpgradeAccountScreenState extends State<UpgradeAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();

  /// Pré-remplissage du pseudo depuis le prénom (suggestion `prenom_NNN`,
  /// quasi toujours disponible) tant que l'utilisateur n'a pas touché au
  /// champ — supprime la friction du « choisis un pseudo unique ».
  bool _usernameEdited = false;

  void _suggestUsernameFromFirstName() {
    if (_usernameEdited) return;
    final first = _firstName.text.trim();
    if (first.isEmpty) return;
    _username.text = generateUsername(first);
  }

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  String _phoneNumber = '';
  DateTime? _birthDate;
  bool _obscure = true;
  bool _checkingUsername = false;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _firstName.addListener(_suggestUsernameFromFirstName);
    // Marqueur funnel : l'utilisateur anonyme a OUVERT l'écran d'upgrade
    // (intention forte). Paire avec `upgrade_completed` côté provider pour
    // mesurer la complétion du formulaire.
    AnalyticsService.instance.logUpgradeStarted();
  }

  late final TapGestureRecognizer _termsTap =
      TapGestureRecognizer()..onTap = () => _openUrl(AppConstants.termsUrl);
  late final TapGestureRecognizer _privacyTap =
      TapGestureRecognizer()
        ..onTap = () => _openUrl(AppConstants.privacyPolicyUrl);

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      /* lien non critique */
    }
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: l.registerBirthDateLabel,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showEmailInUseDialog() async {
    final l = AppLocalizations.of(context);
    final goToLogin = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l.upgradeAccountEmailInUseTitle),
            content: Text(l.upgradeAccountEmailInUseBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.actionCancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.loginButton),
              ),
            ],
          ),
    );
    if (goToLogin != true || !mounted) return;
    // Remplace cet écran par LoginScreen (pour ne pas empiler).
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    if (!_acceptedTerms) {
      _snack(l.registerMustAcceptTerms);
      return;
    }
    final auth = context.read<AuthProvider>();
    setState(() => _checkingUsername = true);
    final available = await auth.isUsernameAvailable(_username.text);
    if (!mounted) return;
    setState(() => _checkingUsername = false);
    if (!available) {
      _snack(l.registerUsernameTaken);
      return;
    }
    final ok = await auth.upgradeWithEmail(
      firstName: _firstName.text,
      lastName: _lastName.text,
      username: _username.text,
      email: _email.text,
      password: _password.text,
      phoneNumber: _phoneNumber.isEmpty ? null : _phoneNumber,
      birthDate: _birthDate,
    );
    if (!mounted) return;
    if (ok) {
      // L'AuthGate observe le nouveau status `awaitingVerification` et
      // affiche EmailVerificationScreen. On retire juste cet écran de la pile.
      Navigator.of(context).pop();
      return;
    }
    // Erreur : on traite spécifiquement l'email déjà utilisé (UX dédiée),
    // sinon snack standard.
    if (auth.error == AppError.emailInUse) {
      await _showEmailInUseDialog();
      return;
    }
    if (auth.error != null) {
      _snack(appErrorLabel(context, auth.error!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().busy;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.upgradeAccountTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Rappel rassurant en haut du formulaire : promesse claire
                // « tu ne perds rien » (linkWithCredential préserve l'uid).
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.upgradeAccountIntro,
                          style: const TextStyle(
                            color: AppColors.dark,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _firstName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l.registerFirstNameLabel,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator:
                      (v) => l.validateRequired(
                        v,
                        label: l.registerFirstNameRequired,
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lastName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l.registerLastNameLabel,
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                  validator:
                      (v) => l.validateRequired(
                        v,
                        label: l.registerLastNameRequired,
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _username,
                  onChanged: (_) => _usernameEdited = true,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.registerUsernameLabel,
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                  validator: l.validateUsername,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.registerEmailLabel,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  validator: l.validateEmail,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickBirthDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l.registerBirthDateLabel,
                      prefixIcon: const Icon(Icons.cake_outlined),
                    ),
                    child: Text(
                      _birthDate == null
                          ? l.actionSelect
                          : formatDate(_birthDate!),
                      style: TextStyle(
                        color: _birthDate == null ? AppColors.gray : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                IntlPhoneField(
                  decoration: InputDecoration(labelText: l.registerPhoneLabel),
                  initialCountryCode: 'CM',
                  languageCode: Localizations.localeOf(context).languageCode,
                  invalidNumberMessage: l.registerPhoneInvalid,
                  disableLengthCheck: true,
                  validator: (phone) {
                    if (phone == null || phone.number.trim().isEmpty) {
                      return null;
                    }
                    try {
                      return phone.isValidNumber()
                          ? null
                          : l.registerPhoneInvalid;
                    } catch (_) {
                      return l.registerPhoneInvalid;
                    }
                  },
                  onChanged:
                      (phone) =>
                          _phoneNumber =
                              phone.number.trim().isEmpty
                                  ? ''
                                  : phone.completeNumber,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l.registerPasswordLabel,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: l.validatePassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: l.registerPasswordConfirmLabel,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  validator:
                      (v) =>
                          v != _password.text
                              ? l.registerPasswordsMismatch
                              : null,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _acceptedTerms,
                      onChanged:
                          (v) => setState(() => _acceptedTerms = v ?? false),
                      activeColor: AppColors.primary,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap:
                            () => setState(
                              () => _acceptedTerms = !_acceptedTerms,
                            ),
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.dark,
                            ),
                            children: [
                              TextSpan(text: l.registerAcceptPrefix),
                              TextSpan(
                                text: l.registerTermsLink,
                                style: const TextStyle(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: _termsTap,
                              ),
                              TextSpan(text: l.registerAcceptAnd),
                              TextSpan(
                                text: l.registerPrivacyLink,
                                style: const TextStyle(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: _privacyTap,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed:
                      (busy || _checkingUsername || !_acceptedTerms)
                          ? null
                          : _submit,
                  child:
                      (busy || _checkingUsername)
                          ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.dark,
                            ),
                          )
                          : Text(l.upgradeAccountSubmit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
