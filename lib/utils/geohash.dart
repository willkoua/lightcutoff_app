import '../config/app_constants.dart';

/// Alphabet base32 du geohash (sans a, i, l, o pour éviter les confusions).
const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Encode une position (lat/lng) en **geohash** : une chaîne courte où deux
/// positions proches partagent un préfixe commun. Sert au ciblage de proximité
/// (filtres de zone, notifications « coupure près de chez moi »).
///
/// [precision] = nombre de caractères (plus c'est long, plus la cellule est
/// petite). Défaut : [AppConstants.geohashPrecision].
String encodeGeohash(
  double lat,
  double lng, {
  int precision = AppConstants.geohashPrecision,
}) {
  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  final hash = StringBuffer();
  var even = true; // on commence par la longitude
  var bit = 0;
  var ch = 0;

  while (hash.length < precision) {
    if (even) {
      final mid = (lngMin + lngMax) / 2;
      if (lng >= mid) {
        ch = (ch << 1) | 1;
        lngMin = mid;
      } else {
        ch = ch << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latMin = mid;
      } else {
        ch = ch << 1;
        latMax = mid;
      }
    }
    even = !even;

    if (++bit == 5) {
      hash.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return hash.toString();
}
