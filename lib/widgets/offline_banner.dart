import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/connectivity_provider.dart';

/// Enrobe l'application et superpose un bandeau « Hors ligne » en haut quand le
/// réseau manque. Branché via `MaterialApp.builder` pour couvrir **toutes** les
/// routes (login, onboarding, shell, détails…).
///
/// Quand hors ligne, le bandeau prend la zone du status bar (`SafeArea`) et on
/// retire le padding haut de [child] (`MediaQuery.removePadding`) pour éviter
/// que les écrans ne ré-insèrent une marge sous le status bar déjà consommé.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<ConnectivityProvider>().isOffline;
    if (!offline) return child;

    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Material(
          color: const Color(0xFF424242),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 18,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l.offlineBannerMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
