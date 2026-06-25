import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../utils/validators.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(
      identifier: _identifier.text,
      password: _password.text,
    );
    if (!ok && mounted && auth.error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(appErrorLabel(context, auth.error!))),
        );
    }
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    final ok = await auth.signInWithGoogle();
    // Au succès, l'AuthGate route automatiquement (profil à compléter ou app).
    if (!ok && mounted && auth.error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(appErrorLabel(context, auth.error!))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().busy;
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lightbulb,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'NJUKA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.loginTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.gray),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _identifier,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l.loginIdentifierLabel,
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: l.validateIdentifier,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l.loginPasswordLabel,
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
                  // « Mot de passe oublié ? » — pré-rempli avec l'identifiant
                  // déjà saisi pour éviter une double saisie.
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed:
                          busy
                              ? null
                              : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder:
                                      (_) => ForgotPasswordScreen(
                                        initialIdentifier:
                                            _identifier.text.trim(),
                                      ),
                                ),
                              ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l.loginForgotPassword),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                            : Text(l.loginButton),
                  ),
                  // Connexion sociale — masquée tant que la config Firebase
                  // Google n'est pas faite (cf. AppConfig.enableGoogleSignIn).
                  if (AppConfig.enableGoogleSignIn) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            l.authOrSeparator,
                            style: const TextStyle(color: AppColors.gray),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _google,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: Text(l.authContinueWithGoogle),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l.loginNoAccount),
                      TextButton(
                        onPressed:
                            busy
                                ? null
                                : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterScreen(),
                                  ),
                                ),
                        child: Text(l.loginRegisterAction),
                      ),
                    ],
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
