import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import 'login_screen.dart';

/// Écran de **récupération** affiché quand `signInAnonymously` échoue au
/// démarrage (offline, ou Anonymous Auth pas activé console). Propose :
/// 1. Réessayer la session anonyme.
/// 2. Se connecter avec un compte existant (entrée vers [LoginScreen]).
///
/// PAS de re-tentative automatique : c'est à l'utilisateur de relancer.
class AnonymousRetryScreen extends StatelessWidget {
  const AnonymousRetryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(l.anonymousRetryTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 72,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  l.anonymousRetryHeading,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.anonymousRetryBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.gray),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    appErrorLabel(context, auth.error!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ongoing,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed:
                      auth.busy
                          ? null
                          : () =>
                              context
                                  .read<AuthProvider>()
                                  .retryAnonymousSignIn(),
                  child:
                      auth.busy
                          ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.dark,
                            ),
                          )
                          : Text(l.anonymousRetryButton),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed:
                      auth.busy
                          ? null
                          : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          ),
                  child: Text(l.anonymousRetryAlreadyAccount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
