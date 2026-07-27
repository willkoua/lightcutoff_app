import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_constants.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';
import '../utils/l10n_helpers.dart';
import '../utils/username_generator.dart';
import '../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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

  // Recognizers pour les liens cliquables CGU / confidentialité dans la case
  // d'acceptation (créés une fois, libérés dans dispose).
  late final TapGestureRecognizer _termsTap =
      TapGestureRecognizer()..onTap = () => _openUrl(AppConstants.termsUrl);
  late final TapGestureRecognizer _privacyTap =
      TapGestureRecognizer()
        ..onTap = () => _openUrl(AppConstants.privacyPolicyUrl);

  @override
  void initState() {
    super.initState();
    _firstName.addListener(_suggestUsernameFromFirstName);
  }

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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    // Acceptation des CGU obligatoire pour créer un compte.
    if (!_acceptedTerms) {
      _snack(l.registerMustAcceptTerms);
      return;
    }
    // Date de naissance et téléphone sont optionnels.
    final auth = context.read<AuthProvider>();
    // Vérifie l'unicité du pseudo avant de créer le compte.
    setState(() => _checkingUsername = true);
    final available = await auth.isUsernameAvailable(_username.text);
    if (!mounted) return;
    setState(() => _checkingUsername = false);
    if (!available) {
      _snack(l.registerUsernameTaken);
      return;
    }
    final ok = await auth.register(
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
      Navigator.of(context).pop();
    } else if (auth.error != null) {
      _snack(appErrorLabel(context, auth.error!));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().busy;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.registerTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                // Date de naissance (sélecteur).
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
                  // Optionnel (tant que la connexion par numéro n'existe pas) :
                  // vide accepté ; le format n'est vérifié que si un numéro est
                  // réellement saisi.
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
                // Acceptation obligatoire des CGU (liens cliquables).
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
                          : Text(l.registerButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
