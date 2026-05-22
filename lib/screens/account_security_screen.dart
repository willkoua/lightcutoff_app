import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/validators.dart';

/// Écran « Sécurité » : changement d'email et de mot de passe.
/// Les deux opérations exigent le **mot de passe actuel** (ré-authentification).
class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité')),
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
                ? 'Un lien de confirmation a été envoyé à la nouvelle adresse. '
                    'Reconnecte-toi avec le nouvel email après confirmation.'
                : (auth.error ?? 'Échec du changement d\'email.'),
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
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Changer l\'email',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _newEmail,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Nouvel email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mot de passe actuel',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: Validators.password,
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
                    : const Text('Changer l\'email'),
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
                ? 'Mot de passe mis à jour.'
                : (auth.error ?? 'Échec du changement de mot de passe.'),
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
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Changer le mot de passe',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mot de passe actuel',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: Validators.password,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _newPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nouveau mot de passe',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
            validator: Validators.password,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirmer le nouveau mot de passe',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
            validator:
                (v) =>
                    v != _newPassword.text
                        ? 'Les mots de passe diffèrent'
                        : null,
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
                    : const Text('Changer le mot de passe'),
          ),
        ],
      ),
    );
  }
}
