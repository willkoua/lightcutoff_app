import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/app_colors.dart';

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
