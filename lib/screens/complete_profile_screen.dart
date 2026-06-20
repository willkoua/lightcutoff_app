import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';
import '../utils/l10n_helpers.dart';
import '../utils/validators.dart';

/// Écran de **complétion de profil** pour un compte social (1er login Google) :
/// l'authentification a réussi mais il n'y a pas encore de profil Firestore
/// (pseudo unique, nom…). Tant que le profil n'est pas créé, l'`AuthGate`
/// maintient l'utilisateur ici (cf. `AuthStatus.profileIncomplete`).
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  String _phoneNumber = '';
  DateTime? _birthDate;
  bool _checkingUsername = false;

  @override
  void initState() {
    super.initState();
    // Préremplit prénom/nom depuis le nom affiché fourni par le provider social.
    final display = context.read<AuthProvider>().pendingDisplayName?.trim();
    if (display != null && display.isNotEmpty) {
      final parts = display.split(RegExp(r'\s+'));
      _firstName.text = parts.first;
      if (parts.length > 1) _lastName.text = parts.sublist(1).join(' ');
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    final auth = context.read<AuthProvider>();
    setState(() => _checkingUsername = true);
    final available = await auth.isUsernameAvailable(_username.text);
    if (!mounted) return;
    setState(() => _checkingUsername = false);
    if (!available) {
      _snack(l.registerUsernameTaken);
      return;
    }
    final ok = await auth.completeProfile(
      firstName: _firstName.text,
      lastName: _lastName.text,
      username: _username.text,
      phoneNumber: _phoneNumber.isEmpty ? null : _phoneNumber,
      birthDate: _birthDate,
    );
    if (!mounted) return;
    if (!ok && auth.error != null) {
      _snack(appErrorLabel(context, auth.error!));
    }
    // Au succès, l'AuthGate bascule automatiquement vers MainShell.
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.busy;
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.completeProfileTitle),
        actions: [
          IconButton(
            tooltip: l.profileLogoutButton,
            icon: const Icon(Icons.logout),
            onPressed: busy ? null : () => auth.logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.completeProfileIntro,
                  style: const TextStyle(color: AppColors.gray),
                ),
                const SizedBox(height: 24),
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
                          : Text(l.completeProfileButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
