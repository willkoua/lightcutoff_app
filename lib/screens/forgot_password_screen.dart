import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../utils/validators.dart';

/// Écran « Mot de passe oublié ». Saisit un email **ou** un pseudo, et
/// déclenche `auth.requestPasswordReset(...)`.
///
/// **Sécurité** : toujours afficher un message générique de succès (« si un
/// compte existe… »), même si l'identifiant n'est pas trouvé — pas de leak
/// de l'existence du compte. Voir aussi `AuthService.sendPasswordResetEmail`
/// qui swallows `user-not-found` côté service.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialIdentifier});

  /// Pré-remplissage optionnel depuis [LoginScreen] (l'utilisateur a tapé
  /// son identifiant avant de cliquer « Mot de passe oublié »).
  final String? initialIdentifier;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _identifier;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _identifier = TextEditingController(text: widget.initialIdentifier ?? '');
  }

  @override
  void dispose() {
    _identifier.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestPasswordReset(identifier: _identifier.text);
    if (!mounted) return;
    if (ok) {
      setState(() => _sent = true);
    } else if (auth.error != null) {
      _snack(appErrorLabel(context, auth.error!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final busy = context.watch<AuthProvider>().busy;
    return Scaffold(
      appBar: AppBar(title: Text(l.forgotPasswordTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child:
                _sent
                    ? _SuccessView(onBack: () => Navigator.of(context).pop())
                    : Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.lock_reset,
                            size: 64,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l.forgotPasswordBody,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.gray),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _identifier,
                            autocorrect: false,
                            autofocus:
                                widget.initialIdentifier == null ||
                                widget.initialIdentifier!.isEmpty,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: l.forgotPasswordIdentifierLabel,
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                            validator: l.validateIdentifier,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: busy ? null : _submit,
                            child:
                                busy
                                    ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.dark,
                                      ),
                                    )
                                    : Text(l.forgotPasswordSubmit),
                          ),
                        ],
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: AppColors.resolved,
        ),
        const SizedBox(height: 16),
        Text(
          l.forgotPasswordSuccess,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.dark),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: onBack,
          child: Text(l.forgotPasswordBackToLogin),
        ),
      ],
    );
  }
}
