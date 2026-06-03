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
}
