import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/region_provider.dart';
import 'screens/onboarding_gate.dart';
import 'services/analytics_service.dart';
import 'theme/app_theme.dart';
import 'utils/nav_key.dart';
import 'widgets/offline_banner.dart';

class NjukaApp extends StatelessWidget {
  const NjukaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        // Fournisseur d'électricité actif (pays + compagnie). Alimenté par le
        // `homeLocation` du profil dès que l'auth/profil change.
        ChangeNotifierProxyProvider<AuthProvider, RegionProvider>(
          create: (_) => RegionProvider(),
          update: (_, auth, region) {
            region!.setHomeCountry(auth.profile?.homeLocation.country);
            return region;
          },
        ),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            title: 'NJUKA',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            navigatorKey: navigatorKey,
            // i18n : Flutter détecte la langue du téléphone et choisit la locale
            // supportée la plus proche (FR ou EN). Pour les autres langues, on
            // retombe sur le 1er supportedLocale (FR — langue d'origine).
            // En debug, [LocaleProvider] peut forcer une locale manuellement
            // (sélecteur dans Paramètres).
            locale: localeProvider.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // Journalise automatiquement les screen_view (Analytics funnel).
            navigatorObservers: [AnalyticsService.instance.observer],
            // Superpose un bandeau « Hors ligne » global au-dessus de toutes les
            // routes (le builder s'exécute sous Localizations/MediaQuery, donc
            // AppLocalizations + le ConnectivityProvider y sont accessibles).
            // + bannière d'environnement (DEV/STAGING) — absente en prod.
            builder: (context, child) {
              Widget content = OfflineBanner(
                child: child ?? const SizedBox.shrink(),
              );
              final envLabel = AppConfig.envBannerLabel;
              if (envLabel != null) {
                content = Banner(
                  message: envLabel,
                  location: BannerLocation.topEnd,
                  color:
                      AppConfig.isDev ? Colors.blueGrey : Colors.deepPurple,
                  child: content,
                );
              }
              return content;
            },
            home: const OnboardingGate(),
          );
        },
      ),
    );
  }
}
