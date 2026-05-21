import '../models/geo.dart';

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
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
