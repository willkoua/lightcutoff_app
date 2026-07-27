import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/app_error.dart';
import '../models/geo.dart';
import '../repositories/location_repository.dart';

/// Implémentation geolocator/geocoding de [LocationRepository].
class LocationService implements LocationRepository {
  /// État d'accès actuel, sans déclencher la demande système.
  @override
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
  @override
  Future<void> openSettings() => Geolocator.openAppSettings();

  /// Récupère la position courante et la zone (reverse-géocodage).
  @override
  Future<LocationResult> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(AppError.locationServicesDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationException(AppError.locationPermissionDenied);
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

    throw const LocationException(AppError.locationNotFound);
  }

  /// Géocodage direct d'une description libre (quartier, ville, adresse) en
  /// coordonnées, puis reverse-géocodage pour renseigner la zone (et surtout le
  /// `countryCode`, qui cloisonne les données par pays). Best-effort mais
  /// mondial : repose sur le géocodeur natif (Android Geocoder / iOS CLGeocoder).
  @override
  Future<LocationResult> locationFromDescription(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const LocationException(AppError.locationNotFound);
    }
    final List<Location> matches;
    try {
      matches = await locationFromAddress(trimmed);
    } catch (_) {
      // Aucun résultat / pas de réseau → traité comme « introuvable ».
      throw const LocationException(AppError.locationNotFound);
    }
    if (matches.isEmpty) {
      throw const LocationException(AppError.locationNotFound);
    }
    final m = matches.first;
    final area = await _reverseGeocode(m.latitude, m.longitude);
    return LocationResult(
      position: GeoPosition(lat: m.latitude, lng: m.longitude),
      area: area,
    );
  }

  Future<GeoArea> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return const GeoArea();
      final p = placemarks.first;
      return GeoArea(
        country: p.country ?? '',
        countryCode: (p.isoCountryCode ?? '').toUpperCase(),
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
