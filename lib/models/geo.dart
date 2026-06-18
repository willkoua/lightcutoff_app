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

  /// Code pays ISO (ex. `CM`, `CA`), issu du géocodage. Sert à **cloisonner les
  /// données par pays** (un utilisateur ne voit que les coupures de son pays).
  /// Vide si le géocodage ne l'a pas fourni (données héritées).
  final String countryCode;
  final String region;
  final String city;
  final String neighborhood;

  const GeoArea({
    this.country = '',
    this.countryCode = '',
    this.region = '',
    this.city = '',
    this.neighborhood = '',
  });

  factory GeoArea.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return GeoArea(
      country: m['country'] as String? ?? '',
      countryCode: m['countryCode'] as String? ?? '',
      region: m['region'] as String? ?? '',
      city: m['city'] as String? ?? '',
      neighborhood: m['neighborhood'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'country': country,
    'countryCode': countryCode,
    'region': region,
    'city': city,
    'neighborhood': neighborhood,
  };

  String get label => [
    neighborhood,
    city,
    region,
    country,
  ].where((s) => s.isNotEmpty).join(', ');
}
