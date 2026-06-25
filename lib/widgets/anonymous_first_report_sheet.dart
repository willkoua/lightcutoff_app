import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../screens/upgrade_account_screen.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';

/// Clé SharedPreferences : marque que la bottom-sheet « garde tes
/// signalements » a déjà été montrée à cet utilisateur **sur cet appareil**.
/// Volontairement non bornée par uid : on ne veut pas spammer l'utilisateur à
/// chaque nouvelle session anonyme (réinstall = nouvel uid mais on accepte
/// que le rappel ne reprenne pas — le but est de l'avoir vu une fois).
const String kAnonymousFirstReportHintSeenKey =
    'anonymous_first_report_hint_seen';

/// Bottom-sheet rappelant à l'utilisateur anonyme que ses signalements et
/// votes sont liés à cet appareil et qu'il les perd en cas de désinstallation.
///
/// Déclenchée **une seule fois par appareil** par
/// [showAnonymousFirstReportHintIfNeeded] après le premier signalement réussi.
class AnonymousFirstReportHintSheet extends StatelessWidget {
  const AnonymousFirstReportHintSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: Icon(
                Icons.bookmark_added_outlined,
                size: 56,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.anonymousFirstReportHintTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              l.anonymousFirstReportHintBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UpgradeAccountScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(l.anonymousFirstReportHintCTA),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.anonymousFirstReportHintLater),
            ),
          ],
        ),
      ),
    );
  }
}

/// Affiche la bottom-sheet si la session est anonyme **et** que le flag
/// SharedPrefs n'est pas encore posé. Marque le flag avant d'afficher (pour
/// que la 1ʳᵉ rendue de la modale soit la seule, même si l'utilisateur
/// déclenche immédiatement un 2ᵉ signalement). No-op silencieux sinon.
Future<void> showAnonymousFirstReportHintIfNeeded(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  if (!auth.isAnonymous) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(kAnonymousFirstReportHintSeenKey) ?? false) return;
  await prefs.setBool(kAnonymousFirstReportHintSeenKey, true);
  // Funnel : 1ᵉʳ signalement anonyme = preuve d'engagement réel. Posé en même
  // temps que le flag pour rester atomique (1 fois par appareil).
  unawaited(AnalyticsService.instance.logAnonymousFirstReport());
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AnonymousFirstReportHintSheet(),
  );
}
