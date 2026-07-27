import 'package:cloud_firestore/cloud_firestore.dart';

import 'geo.dart';

/// Appareil enregistré pour les notifications push.
///
/// Collection `devices` dont **l'id du document est le token FCM** (un device =
/// un token = un doc), ce qui rend l'enregistrement idempotent (upsert).
class Device {
  /// Token FCM = identifiant du document.
  final String token;
  final String userId;

  /// `android` | `ios`.
  final String platform;

  /// Zone de résidence, pour le ciblage « à proximité » (v1).
  final GeoArea homeLocation;

  /// Geohash de la zone, pour le ciblage par rayon (v2).
  final String? geohash;

  /// Position **exacte** (lat/lng) capturée à l'enregistrement. Permet à la
  /// Cloud Function de filtrer les destinataires à la **distance exacte** (le
  /// geohash seul est trop grossier pour un rayon serré). Lecture réservée à
  /// l'Admin SDK / propriétaire (collection `devices` non lisible par les
  /// tiers). `null` si la position n'était pas disponible.
  final ({double lat, double lng})? position;

  /// Permet à l'utilisateur de couper les alertes sans se désinscrire.
  final bool fcmEnabled;

  /// Dernière mise à jour — sert au nettoyage des tokens périmés.
  final DateTime? updatedAt;

  const Device({
    required this.token,
    required this.userId,
    this.platform = '',
    this.homeLocation = const GeoArea(),
    this.geohash,
    this.position,
    this.fcmEnabled = true,
    this.updatedAt,
  });

  factory Device.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    final pos = map['position'] as Map<String, dynamic>?;
    return Device(
      token: doc.id,
      userId: map['userId'] as String? ?? '',
      platform: map['platform'] as String? ?? '',
      homeLocation: GeoArea.fromMap(
        map['homeLocation'] as Map<String, dynamic>?,
      ),
      geohash: map['geohash'] as String?,
      position:
          pos != null
              ? (lat: (pos['lat'] as num).toDouble(), lng: (pos['lng'] as num).toDouble())
              : null,
      fcmEnabled: map['fcmEnabled'] as bool? ?? true,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Données écrites lors de l'enregistrement (set + merge). Le token étant
  /// l'id du document, il n'est pas dupliqué dans les champs.
  Map<String, dynamic> toWriteMap() => {
    'userId': userId,
    'platform': platform,
    'homeLocation': homeLocation.toMap(),
    'geohash': geohash,
    if (position != null)
      'position': {'lat': position!.lat, 'lng': position!.lng},
    'fcmEnabled': fcmEnabled,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
