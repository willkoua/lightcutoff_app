import '../models/app_error.dart';
import '../models/geo.dart';

/// Erreur de localisation portant un [AppError] (code), traduit en message
/// utilisateur côté UI via `appErrorLabel`. La couche service n'ayant pas de
/// `BuildContext`, elle ne produit jamais de texte localisé directement.
class LocationException implements Exception {
  final AppError code;
  const LocationException(this.code);
}

/// État d'accès à la localisation, indépendant de l'implémentation.
enum LocationAccess {
  granted,
  denied, // refusé mais on peut re-demander
  deniedForever, // refus définitif → réglages système requis
  serviceDisabled, // localisation désactivée sur l'appareil
}

class LocationResult {
  final GeoPosition position;
  final GeoArea area;
  const LocationResult({required this.position, required this.area});
}

/// Contrat d'accès à la localisation de l'appareil.
abstract class LocationRepository {
  Future<LocationAccess> checkAccess();
  Future<void> openSettings();
  Future<LocationResult> getCurrentLocation();

  /// Dernière position connue de l'appareil (lecture du cache système) :
  /// **instantanée**, sans demande de permission ni fix GPS ni reverse-géocodage.
  /// Renvoie `null` si aucune position n'est en cache (ou plateforme non
  /// supportée — iOS ne persiste pas de dernière position). Sert à ouvrir la
  /// carte directement sur l'utilisateur, sans afficher d'abord une position par
  /// défaut (Cameroun) puis « sauter ».
  Future<GeoPosition?> lastKnownPosition();

  /// Résout une **position décrite manuellement** ([query] : quartier, ville,
  /// adresse…) en coordonnées + zone, via géocodage direct. Permet de signaler
  /// sans GPS. Mondial (pas spécifique à un pays). Lève
  /// [LocationException]`(AppError.locationNotFound)` si la description ne
  /// correspond à aucun lieu.
  Future<LocationResult> locationFromDescription(String query);

  /// Suggestions de lieux pour une saisie partielle (autocomplete du
  /// formulaire « Décrire ma position », 2026-08-13 — Stadia Maps/OSM).
  /// [focus] (position GPS si disponible) fait remonter les lieux proches en
  /// tête SANS exclure le reste du monde (cas diaspora). Liste vide si le
  /// service est indisponible — l'appelant retombe alors sur
  /// [locationFromDescription] (géocodeur natif).
  Future<List<LocationResult>> placeSuggestions(
    String query, {
    GeoPosition? focus,
  });
}
