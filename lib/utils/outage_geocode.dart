import 'package:latlong2/latlong.dart';

import '../repositories/location_repository.dart';

/// Construction d'une **zone d'impact approximative** pour une coupure
/// programmée à partir de sa description (liste de rues/repères).
///
/// Stratégie (robuste) : on géocode le **centre du quartier** puis chaque
/// **rue**, on **écarte les outliers** (points trop loin du centre — ex. un
/// repère homonyme géocodé dans un autre secteur), et on renvoie les points
/// retenus + un **cercle englobant**. Un outlier filtré ne déforme donc pas la
/// zone. Tout est client-side (géocodeur natif, sans clé API).

/// Distance max (mètres) entre une rue et le centre du quartier pour garder le
/// point. Au-delà = outlier (homonyme, mauvais appariement) → ignoré.
const double kOutageOutlierMaxM = 4000;

/// Nombre max de rues géocodées (borne la latence et les appels géocodeur).
const int kOutageMaxStreets = 12;

/// Rayon du cercle englobant (repli si aucune rue résolue), borné.
const double kOutageZoneMinRadiusM = 400;
const double kOutageZoneMaxRadiusM = 3000;

/// Rayon du petit cercle (buffer) tracé autour de CHAQUE rue géocodée : matérialise
/// l'incertitude du géocodage d'une rue (~qqs centaines de m) sans couvrir tout
/// le quartier. Les buffers se fondent là où les rues sont proches.
const double kOutageStreetBufferM = 300;

/// Zone d'impact calculée : centre (quartier), points de rues retenus, rayon.
class OutageZone {
  const OutageZone({
    required this.center,
    required this.points,
    required this.radiusM,
  });

  final LatLng center;
  final List<LatLng> points;
  final double radiusM;
}

final _noiseTokens = <String>{
  'adjacent customers',
  'and adjacent customers',
  'environs',
  'and environs',
  'and surrounding areas',
  'and surrounding environs',
  'surrounding areas',
  'surrounding environs',
  'and its surrounding areas',
};

/// Découpe une description en **noms de rues/repères géocodables**. **Pure.**
/// - sépare par virgules ;
/// - retire le bruit (« & adjacent customers », « and environs »…) ;
/// - nettoie les préfixes vagues (« parts of », « the whole of ») ;
/// - ignore les jetons trop courts ou non localisables ; dédoublonne ;
/// - borne à [kOutageMaxStreets].
List<String> parseOutageStreets(String reason) {
  if (reason.trim().isEmpty) return const [];
  // Uniformise les « & » en virgules, coupe la ponctuation finale.
  final normalized = reason.replaceAll('&', ',');
  final seen = <String>{};
  final out = <String>[];
  for (var raw in normalized.split(',')) {
    var s = raw.trim();
    // Retire un préfixe vague éventuel.
    s = s.replaceAll(
      RegExp(r'^(parts? of|the whole of)\s+', caseSensitive: false),
      '',
    );
    s = s.replaceAll(RegExp(r'[.\s]+$'), '').trim();
    if (s.length < 4) continue;
    final low = s.toLowerCase();
    if (_noiseTokens.contains(low)) continue;
    // Jetons génériques non localisables seuls.
    if (low == 'environs' || low.endsWith(' customers')) continue;
    if (seen.add(low)) out.add(s);
    if (out.length >= kOutageMaxStreets) break;
  }
  return out;
}

/// Rayon englobant les [points] depuis [center], borné. **Pure.**
double boundingRadiusM(LatLng center, List<LatLng> points) {
  const d = Distance();
  var maxM = 0.0;
  for (final p in points) {
    final m = d.as(LengthUnit.Meter, center, p);
    if (m > maxM) maxM = m;
  }
  // + marge de 20 % pour que les points ne touchent pas le bord.
  final r = maxM * 1.2;
  if (r < kOutageZoneMinRadiusM) return kOutageZoneMinRadiusM;
  if (r > kOutageZoneMaxRadiusM) return kOutageZoneMaxRadiusM;
  return r;
}

/// Géocode le quartier + ses rues et construit la [OutageZone]. Les appels
/// géocodeur sont **séquentiels** (le géocodeur natif tolère mal les rafales)
/// et **mis en cache** par requête via [cache] (réutilisé entre les cartes).
/// `null` si même le centre du quartier est introuvable.
Future<OutageZone?> geocodeOutageZone({
  required String quartier,
  required String ville,
  required String countryLabel,
  required String reason,
  required LocationRepository repo,
  Map<String, LatLng?>? cache,
}) async {
  final store = cache ?? <String, LatLng?>{};
  final suffix = [ville, countryLabel].where((s) => s.isNotEmpty).join(', ');

  Future<LatLng?> geocode(String name) async {
    final query = suffix.isEmpty ? name : '$name, $suffix';
    if (store.containsKey(query)) return store[query];
    try {
      final res = await repo.locationFromDescription(query);
      final p = LatLng(res.position.lat, res.position.lng);
      store[query] = p;
      return p;
    } catch (_) {
      store[query] = null;
      return null;
    }
  }

  final center = await geocode(quartier);
  if (center == null) return null;

  const d = Distance();
  final points = <LatLng>[];
  for (final street in parseOutageStreets(reason)) {
    final p = await geocode(street);
    if (p == null) continue;
    // Outlier : trop loin du centre du quartier → ignoré.
    if (d.as(LengthUnit.Meter, center, p) > kOutageOutlierMaxM) continue;
    points.add(p);
  }

  return OutageZone(
    center: center,
    points: points,
    radiusM: points.isEmpty ? 1200 : boundingRadiusM(center, points),
  );
}
