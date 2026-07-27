import 'package:cloud_firestore/cloud_firestore.dart';

/// Confirmation d'une coupure existante par un utilisateur.
/// Stockée dans la sous-collection `reports/{reportId}/confirmations/{uid}`,
/// l'id du document étant l'uid (un seul vote par utilisateur).
class Confirmation {
  final String userId;
  final DateTime? createdAt;

  /// Geohash **grossier** (précision 6, ≈1,2 km) de la position du confirmeur au
  /// moment du vote. Conservé pour estimer l'**étendue** d'une coupure.
  /// `null` si la position n'était pas disponible.
  final String? geohash;

  /// Position **exacte** (lat/lng) du confirmeur au moment du vote. Sert au
  /// ciblage 500 m des notifications de proximité (Cloud Function
  /// `onConfirmationCreated`, via l'Admin SDK). **Lecture verrouillée** aux
  /// règles Firestore : seuls le propriétaire du vote et les admins peuvent
  /// lire une confirmation → l'anonymat vis-à-vis des tiers (y compris l'auteur
  /// du signalement) est préservé. `null` si la position n'était pas disponible.
  final ({double lat, double lng})? position;

  const Confirmation({
    required this.userId,
    this.createdAt,
    this.geohash,
    this.position,
  });

  factory Confirmation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    final pos = map['position'] as Map<String, dynamic>?;
    return Confirmation(
      userId: doc.id,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      geohash: map['geohash'] as String?,
      position:
          pos != null
              ? (lat: (pos['lat'] as num).toDouble(), lng: (pos['lng'] as num).toDouble())
              : null,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'createdAt': FieldValue.serverTimestamp(),
    if (geohash != null) 'geohash': geohash,
    if (position != null)
      'position': {'lat': position!.lat, 'lng': position!.lng},
  };
}
