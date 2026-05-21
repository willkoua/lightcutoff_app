import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo.dart';

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
}

/// État d'accès à la localisation, indépendant de geolocator.
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

class LocationService {
  /// État d'accès actuel, sans déclencher la demande système.
  Future<LocationAccess> checkAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    final permission = await Geolocator.checkPermission();
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationAccess.granted;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
    }
  }

  /// Ouvre les réglages de l'app (pour réactiver une permission refusée).
  Future<void> openSettings() => Geolocator.openAppSettings();

  /// Récupère la position courante et la zone (reverse-géocodage).
  Future<LocationResult> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'La localisation est désactivée. Activez-la pour signaler une coupure.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Permission de localisation refusée.',
      );
    }

    final pos = await _resolvePosition();
    final area = await _reverseGeocode(pos.latitude, pos.longitude);
    return LocationResult(
      position: GeoPosition(lat: pos.latitude, lng: pos.longitude),
      area: area,
    );
  }

  /// Tente une position fraîche (avec timeout), puis se rabat sur la dernière
  /// position connue. Lève une erreur explicite si rien n'est disponible.
  Future<Position> _resolvePosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      // ignore: on tente la dernière position connue ci-dessous
    } catch (_) {
      // idem
    }

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return last;

    throw const LocationException(
      'Position introuvable. Définissez une position dans l\'émulateur '
      '(menu ··· → Location) ou réessayez en extérieur.',
    );
  }

  Future<GeoArea> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return const GeoArea();
      final p = placemarks.first;
      return GeoArea(
        country: p.country ?? '',
        region: p.administrativeArea ?? '',
        city: p.locality ?? '',
        neighborhood: p.subLocality ?? '',
      );
    } catch (_) {
      // Le reverse-géocodage est best-effort : la position GPS suffit.
      return const GeoArea();
    }
  }
}
