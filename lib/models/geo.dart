/// Coordonnées GPS précises.
class GeoPosition {
  final double lat;
  final double lng;

  const GeoPosition({required this.lat, required this.lng});

  factory GeoPosition.fromMap(Map<String, dynamic> map) => GeoPosition(
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng};
}

/// Découpage administratif lisible (issu du reverse-géocodage).
class GeoArea {
  final String country;
  final String region;
  final String city;
  final String neighborhood;

  const GeoArea({
    this.country = '',
    this.region = '',
    this.city = '',
    this.neighborhood = '',
  });

  factory GeoArea.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return GeoArea(
      country: m['country'] as String? ?? '',
      region: m['region'] as String? ?? '',
      city: m['city'] as String? ?? '',
      neighborhood: m['neighborhood'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'country': country,
        'region': region,
        'city': city,
        'neighborhood': neighborhood,
      };

  String get label =>
      [neighborhood, city, region, country].where((s) => s.isNotEmpty).join(', ');
}
