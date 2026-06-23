import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../theme/app_colors.dart';

/// Bannière « filtre actif » réutilisée par la **Liste** et la **Carte** :
/// signale qu'un filtre (proximité, statut, recherche…) restreint l'affichage,
/// et propose de **tout réafficher** d'un tap. Sans elle, sur la carte, des
/// signalements masqués par le filtre proximité passent pour un bug.
class ActiveFiltersBanner extends StatelessWidget {
  const ActiveFiltersBanner({
    super.key,
    required this.count,
    required this.onClear,
  });

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.homeActiveFilters(count),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Text(
              l.homeClearFilters,
              style: const TextStyle(
                color: AppColors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
