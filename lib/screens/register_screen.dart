import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';
import '../utils/l10n_helpers.dart';
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  String _phoneNumber = '';
  DateTime? _birthDate;
  bool _obscure = true;
  bool _checkingUsername = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
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
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: (busy || _checkingUsername) ? null : _submit,
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
