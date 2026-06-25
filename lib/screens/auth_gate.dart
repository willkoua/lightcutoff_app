import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/region_provider.dart';
import '../providers/report_provider.dart';
import 'anonymous_retry_screen.dart';
import 'complete_profile_screen.dart';
import 'email_verification_screen.dart';
import 'main_shell.dart';
import 'splash_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;
    switch (status) {
      case AuthStatus.unknown:
        return const SplashScreen();
      case AuthStatus.anonymous:
      case AuthStatus.authenticated:
        // ReportProvider est alimenté par le pays actif (RegionProvider) pour
        // cloisonner les coupures : chaque utilisateur ne voit que celles de
        // son pays. Identique en session anonyme et authentifiée — les murs
        // d'upgrade (Profil, Stats, suivi quartier) sont gérés dans MainShell.
        return ChangeNotifierProxyProvider<RegionProvider, ReportProvider>(
          create: (_) => ReportProvider(),
          update: (_, region, report) {
            // Mode admin « monde » → pas de cloisonnement pays NI de proximité.
            report!.setWorldwide(region.worldwide);
            report.setCountryFilter(
              region.worldwide ? null : region.activeCountry,
            );
            // Filtre service (Tout / Élec / Eau), persisté côté RegionProvider.
            report.setServiceFilter(region.serviceFilter);
            return report;
          },
          child: const MainShell(),
        );
      case AuthStatus.awaitingVerification:
        return const EmailVerificationScreen();
      case AuthStatus.profileIncomplete:
        return const CompleteProfileScreen();
      case AuthStatus.unauthenticated:
        // Échec auto sign-in anonyme (offline, ou Anonymous Auth pas activé) :
        // écran « Réessayer » + entrée secondaire vers LoginScreen pour les
        // utilisateurs qui ont déjà un compte. Pas de re-tentative auto.
        return const AnonymousRetryScreen();
    }
  }
}
