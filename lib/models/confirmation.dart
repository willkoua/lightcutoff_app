import 'package:cloud_firestore/cloud_firestore.dart';

/// Confirmation d'une coupure existante par un utilisateur.
/// Stockée dans la sous-collection `reports/{reportId}/confirmations/{uid}`,
/// l'id du document étant l'uid (un seul vote par utilisateur).
class Confirmation {
  final String userId;
  final DateTime? createdAt;

  /// Geohash **grossier** (précision 6, ≈1,2 km) de la position du confirmeur au
  /// moment du vote. Conservé pour pouvoir, plus tard, estimer l'**étendue** d'une
  /// coupure (cercle d'emprise). Jamais de lat/lng exact ; lecture restreinte par
  /// les règles → anonymat préservé. `null` si la position n'était pas disponible.
  final String? geohash;

  const Confirmation({required this.userId, this.createdAt, this.geohash});

  factory Confirmation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Confirmation(
      userId: doc.id,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      geohash: map['geohash'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'createdAt': FieldValue.serverTimestamp(),
    if (geohash != null) 'geohash': geohash,
  };
}
