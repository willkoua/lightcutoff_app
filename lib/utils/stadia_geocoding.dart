import '../models/geo.dart';
import '../repositories/location_repository.dart';

/// Parsing PUR de la réponse GeoJSON de l'autocomplete Stadia Maps
/// (`/geocoding/v1/autocomplete`, moteur Pelias/OSM) — séparé de l'I/O pour
/// être testable. Schéma vérifié en live le 2026-08-13 :
/// `features[].geometry.coordinates = [lng, lat]` ;
/// `properties` : `label`, `name`, `country`, `country_code`, `region`,
/// `locality`, `county`, `layer` (`venue`/`locality`/`neighbourhood`…).
List<LocationResult> parseStadiaAutocomplete(Map<String, dynamic> json) {
  final features = json['features'];
  if (features is! List) return const [];
  final out = <LocationResult>[];
  for (final f in features) {
    if (f is! Map<String, dynamic>) continue;
    final geometry = f['geometry'];
    final props = f['properties'];
    if (geometry is! Map<String, dynamic> || props is! Map<String, dynamic>) {
      continue;
    }
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) continue;
    final lng = coords[0];
    final lat = coords[1];
    if (lng is! num || lat is! num) continue;

    String s(dynamic v) => v is String ? v : '';
    final layer = s(props['layer']);
    // `name` d'un lieu précis (commerce, quartier) devient le « quartier »
    // affiché ; pour une ville (`locality`), le nom EST la ville.
    final name = s(props['name']);
    final locality = s(props['locality']);
    final city = locality.isNotEmpty ? locality : s(props['county']);
    out.add(
      LocationResult(
        position: GeoPosition(lat: lat.toDouble(), lng: lng.toDouble()),
        area: GeoArea(
          country: s(props['country']),
          countryCode: s(props['country_code']).toUpperCase(),
          region: s(props['region']),
          city: layer == 'locality' && city.isEmpty ? name : city,
          neighborhood: layer == 'locality' ? '' : name,
        ),
      ),
    );
  }
  return out;
}
