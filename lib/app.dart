import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/onboarding_gate.dart';
import 'theme/app_theme.dart';
import 'utils/nav_key.dart';

class NjukaApp extends StatelessWidget {
  const NjukaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: MaterialApp(
        title: 'NJUKA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        navigatorKey: navigatorKey,
        // i18n : Flutter détecte la langue du téléphone et choisit la locale
        // supportée la plus proche (FR ou EN). Pour les autres langues, on
        // retombe sur le 1er supportedLocale (FR — langue d'origine du projet).
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingGate(),
      ),
    );
  }
}
