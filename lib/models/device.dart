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
    this.fcmEnabled = true,
    this.updatedAt,
  });

  factory Device.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Device(
      token: doc.id,
      userId: map['userId'] as String? ?? '',
      platform: map['platform'] as String? ?? '',
      homeLocation: GeoArea.fromMap(
        map['homeLocation'] as Map<String, dynamic>?,
      ),
      geohash: map['geohash'] as String?,
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
    'fcmEnabled': fcmEnabled,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
