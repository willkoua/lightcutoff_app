import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/report_provider.dart';
import '../repositories/location_repository.dart';
import '../theme/app_colors.dart';

/// Bandeau affiché quand la localisation n'est PAS accordée : prévient que les
/// alertes de proximité ne fonctionneront pas (sinon échec silencieux — on
/// attend des notifs qui ne viendront jamais) et offre un bouton pour activer.
/// Se masque de lui-même dès que l'accès est accordé.
class LocationAlertsBanner extends StatefulWidget {
  const LocationAlertsBanner({super.key});

  @override
  State<LocationAlertsBanner> createState() => _LocationAlertsBannerState();
}

class _LocationAlertsBannerState extends State<LocationAlertsBanner> {
  LocationAccess? _access;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final a = await context.read<ReportProvider>().checkLocationAccess();
    if (mounted) setState(() => _access = a);
  }

  Future<void> _activate() async {
    setState(() => _working = true);
    final a = await context.read<ReportProvider>().requestLocationForAlerts();
    if (mounted) {
      setState(() {
        _access = a;
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tant qu'on ne sait pas (null) ou si c'est accordé : rien à afficher.
    if (_access == null || _access == LocationAccess.granted) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            const Icon(Icons.location_off, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.locationOffBannerText,
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
            ),
            const SizedBox(width: 4),
            _working
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: _activate,
                    child: Text(l.locationOffBannerAction),
                  ),
          ],
        ),
      ),
    );
  }
}
