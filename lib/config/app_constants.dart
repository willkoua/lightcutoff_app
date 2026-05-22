/// Constantes métier centralisées : rayons de proximité, limites des médias,
/// limites de saisie. Regroupées ici pour rester cohérentes entre l'UI, les
/// providers et les utilitaires (source unique de vérité).
///
/// Note : la limite de taille média est aussi appliquée côté serveur dans
/// `storage.rules` — garder les deux valeurs synchronisées.
class AppConstants {
  AppConstants._();

  // --- Proximité (mètres) ---

  /// Rayon en-deçà duquel deux coupures sont considérées identiques
  /// (détection de doublon lors d'un nouveau signalement).
  static const double duplicateRadiusMeters = 500;

  /// Rayon du filtre « à proximité » appliqué à la liste et à la carte.
  static const double nearbyFilterRadiusMeters = 5000;

  // --- Médias des signalements ---

  /// Côté le plus long (px) au-delà duquel une image fixe est redimensionnée.
  static const int maxMediaDimension = 1280;

  /// Taille maximale d'un média uploadé (octets). Doit rester ≤ la règle
  /// Storage (`storage.rules`).
  static const int maxMediaBytes = 8 * 1024 * 1024;

  /// Qualité JPEG de ré-encodage après redimensionnement (0–100).
  static const int mediaJpegQuality = 85;

  // --- Saisie ---

  /// Longueur maximale de la description d'un signalement (caractères).
  static const int maxDescriptionLength = 500;
}
