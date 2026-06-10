import 'package:flutter/material.dart';

/// Couleurs de la charte graphique Lightcutoff (NJUKA).
class AppColors {
  AppColors._();

  // Couleurs principales
  static const Color primary = Color(0xFFF88E01); // Jaune / ambre
  static const Color dark = Color(0xFF1A1A1A); // Fond charbon de marque
  static const Color gray = Color(0xFF4C4C4C); // Gris OTF
  static const Color white = Color(0xFFFFFFFF);

  // Couleurs d'accompagnement
  static const Color rose = Color(0xFFE76392);
  static const Color orange = Color(0xFFEA5713);
  static const Color lightBrown = Color(0xFFF2A04D);

  // Statuts de coupure
  static const Color ongoing = orange; // coupure en cours
  static const Color resolved = Color(0xFF2E9E5B); // rétabli

  // Coupures officielles planifiées (Eneo) — bleu « info », distinct de l'ambre
  // des signalements communautaires.
  static const Color planned = Color(0xFF1B6EF3);
}
