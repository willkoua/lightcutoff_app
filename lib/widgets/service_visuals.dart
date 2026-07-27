import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';

/// Icône emblématique d'un service public (utilisée chips/marqueurs/sélecteur).
IconData serviceTypeIcon(ServiceType service) {
  switch (service) {
    case ServiceType.electricity:
      return Icons.bolt;
    case ServiceType.water:
      return Icons.water_drop;
  }
}

/// Couleur de marque d'un service :
/// - électricité = `AppColors.ongoing` (ambre)
/// - eau         = `AppColors.water`   (sky-500)
/// Couleurs **service**, pas statut — pour le statut « rétabli » on conserve
/// la palette `AppColors.resolved` (vert) commune aux deux services.
Color serviceTypeColor(ServiceType service) {
  switch (service) {
    case ServiceType.electricity:
      return AppColors.ongoing;
    case ServiceType.water:
      return AppColors.water;
  }
}

/// Icône d'**état** d'un signalement, adaptée au service.
/// - élec  : `flash_off` (en cours) / `flash_on` (rétabli) — sémantique
///           « courant coupé » vs « courant revenu ».
/// - eau   : `water_drop_outlined` (en cours, goutte vide) / `water_drop`
///           (rétabli, goutte pleine) — sémantique « pas d'eau » vs
///           « eau revenue ».
/// Permet d'éviter d'afficher un éclair ⚡ sur une coupure d'eau (incohérent).
IconData serviceStatusIcon(ServiceType service, {required bool ongoing}) {
  switch (service) {
    case ServiceType.electricity:
      return ongoing ? Icons.flash_off : Icons.flash_on;
    case ServiceType.water:
      return ongoing ? Icons.water_drop_outlined : Icons.water_drop;
  }
}

/// Icône **générale** (indépendante du service) indiquant si une coupure est
/// imprévue ou programmée. Identique pour l'électricité et l'eau, pour signaler
/// d'un coup d'œil la nature du signalement.
IconData outageTypeIcon(OutageType type) {
  switch (type) {
    case OutageType.unplanned:
      return Icons.warning_amber_rounded;
    case OutageType.scheduled:
      return Icons.event_outlined;
  }
}

/// Chip identifiant le service d'un signalement (⚡ Électricité / 💧 Eau).
/// Couleur de marque tirée de [serviceTypeColor] — différencie l'élec (ambre)
/// de l'eau (bleu sky) au premier coup d'œil. Partagé entre la carte report et
/// l'écran de détail pour rester cohérent.
class ServiceChip extends StatelessWidget {
  const ServiceChip({super.key, required this.service});

  final ServiceType service;

  @override
  Widget build(BuildContext context) {
    final color = serviceTypeColor(service);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(serviceTypeIcon(service), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            serviceTypeLabel(context, service),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
