import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../utils/validators.dart';

/// Écran « Sécurité » : changement d'email et de mot de passe.
/// Les deux opérations exigent le **mot de passe actuel** (ré-authentification).
class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).securityTitle)),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChangeEmailForm(),
              SizedBox(height: 32),
              _ChangePasswordForm(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeEmailForm extends StatefulWidget {
  const _ChangeEmailForm();
  @override
  State<_ChangeEmailForm> createState() => _ChangeEmailFormState();
}

class _ChangeEmailFormState extends State<_ChangeEmailForm> {
  final _formKey = GlobalKey<FormState>();
  final _newEmail = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newEmail.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final l = AppLocalizations.of(context);
    final ok = await auth.changeEmail(
      newEmail: _newEmail.text,
      currentPassword: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l.securityChangeEmailSuccess
                : (auth.error != null
                    ? appErrorLabel(context, auth.error!)
                    : l.securityChangeEmailFailed),
          ),
        ),
      );
    if (ok) {
      _newEmail.clear();
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.securityChangeEmailHeading,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _newEmail,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l.securityNewEmailLabel,
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            validator: l.validateEmail,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l.securityCurrentPasswordLabel,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            validator: l.validatePassword,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child:
                _busy
                    ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.dark,
                      ),
                    )
                    : Text(l.securityChangeEmailButton),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordForm extends StatefulWidget {
  const _ChangePasswordForm();
  @override
  State<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<_ChangePasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final l = AppLocalizations.of(context);
    final ok = await auth.changePassword(
      newPassword: _newPassword.text,
      currentPassword: _current.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l.securityChangePasswordSuccess
                : (auth.error != null
                    ? appErrorLabel(context, auth.error!)
                    : l.securityChangePasswordFailed),
          ),
        ),
      );
    if (ok) {
      _current.clear();
      _newPassword.clear();
      _confirm.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.securityChangePasswordHeading,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l.securityCurrentPasswordLabel,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            validator: l.validatePassword,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _newPassword,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l.securityNewPasswordLabel,
              prefixIcon: const Icon(Icons.lock_reset_outlined),
            ),
            validator: l.validatePassword,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l.securityConfirmNewPasswordLabel,
              prefixIcon: const Icon(Icons.lock_reset_outlined),
            ),
            validator:
                (v) =>
                    v != _newPassword.text ? l.registerPasswordsMismatch : null,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child:
                _busy
                    ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.dark,
                      ),
                    )
                    : Text(l.securityChangePasswordButton),
          ),
        ],
      ),
    );
  }
}
