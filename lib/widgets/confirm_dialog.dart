import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../theme/app_colors.dart';

/// Affiche un dialog de validation oui/non et renvoie `true` si l'utilisateur
/// confirme. Factorisé pour les actions sensibles (confirmer une coupure,
/// déclarer le retour du courant) déclenchées depuis la liste, la carte et le
/// détail — évite les taps accidentels.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.actionCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.dark,
              ),
              child: Text(confirmLabel),
            ),
          ],
        ),
  );
  return ok ?? false;
}
