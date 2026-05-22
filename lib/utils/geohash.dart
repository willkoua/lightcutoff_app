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

// Tables d'adjacence (algorithme classique movable-type). Index 0 = longueur
// paire, index 1 = longueur impaire.
const Map<String, List<String>> _neighborChars = {
  'n': ['p0r21436x8zb9dcf5h7kjnmqesgutwvy', 'bc01fg45238967deuvhjyznpkmstqrwx'],
  's': ['14365h7k9dcfesgujnmqp0r2twvyx8zb', '238967debc01fg45kmstqrwxuvhjyznp'],
  'e': ['bc01fg45238967deuvhjyznpkmstqrwx', 'p0r21436x8zb9dcf5h7kjnmqesgutwvy'],
  'w': ['238967debc01fg45kmstqrwxuvhjyznp', '14365h7k9dcfesgujnmqp0r2twvyx8zb'],
};
const Map<String, List<String>> _borderChars = {
  'n': ['prxz', 'bcfguvyz'],
  's': ['028b', '0145hjnp'],
  'e': ['bcfguvyz', 'prxz'],
  'w': ['0145hjnp', '028b'],
};

/// Cellule adjacente à [hash] dans la direction [dir] ('n','s','e','w').
String _adjacent(String hash, String dir) {
  final last = hash[hash.length - 1];
  var parent = hash.substring(0, hash.length - 1);
  final type = hash.length % 2; // 0 = paire, 1 = impaire
  if (_borderChars[dir]![type].contains(last) && parent.isNotEmpty) {
    parent = _adjacent(parent, dir);
  }
  return parent + _base32[_neighborChars[dir]![type].indexOf(last)];
}

/// Les 8 cellules voisines de [hash] (N, S, E, W puis diagonales).
List<String> geohashNeighbors(String hash) {
  final n = _adjacent(hash, 'n');
  final s = _adjacent(hash, 's');
  return [
    n,
    s,
    _adjacent(hash, 'e'),
    _adjacent(hash, 'w'),
    _adjacent(n, 'e'),
    _adjacent(n, 'w'),
    _adjacent(s, 'e'),
    _adjacent(s, 'w'),
  ];
}

/// Précision geohash dont la cellule contient un rayon de [radiusMeters]
/// (sa plus petite dimension ≥ rayon → centre + voisines couvrent le disque).
int geohashPrecisionForRadius(double radiusMeters) {
  if (radiusMeters <= 153) return 7;
  if (radiusMeters <= 610) return 6;
  if (radiusMeters <= 4890) return 5;
  if (radiusMeters <= 19500) return 4;
  if (radiusMeters <= 156000) return 3;
  if (radiusMeters <= 625000) return 2;
  return 1;
}

/// Préfixes geohash couvrant le disque (centre + 8 voisines), à utiliser comme
/// bornes de requête Firestore puis à affiner par distance exacte.
List<String> geohashesCovering(double lat, double lng, double radiusMeters) {
  final precision = geohashPrecisionForRadius(radiusMeters);
  final center = encodeGeohash(lat, lng, precision: precision);
  return [center, ...geohashNeighbors(center)];
}
