import 'package:cloud_firestore/cloud_firestore.dart';

/// Déclaration « le courant est revenu chez moi » par un utilisateur.
///
/// Stockée dans `reports/{reportId}/restorations/{uid}` — l'id du document
/// étant l'uid, on garantit **un seul vote par utilisateur**.
///
/// Le mécanisme est symétrique à [Confirmation] : à la création, une Cloud
/// Function ([onRestorationCreated]) incrémente `restorationCount` sur le
/// report parent et bascule le `status` en `resolved` lorsque le seuil est
/// franchi (cf. [AppConstants.restorationMinVotes] /
/// [AppConstants.restorationRatio]).
class Restoration {
  final String userId;
  final DateTime? createdAt;

  /// Geohash **grossier** (précision 6, ≈1,2 km) de la position du confirmeur au
  /// moment du vote. Symétrique à [Confirmation.geohash] : conservé pour pouvoir,
  /// plus tard, estimer l'**étendue** du rétablissement d'une coupure. Jamais de
  /// lat/lng exact ; lecture restreinte par les règles → anonymat préservé.
  /// `null` si la position n'était pas disponible.
  final String? geohash;

  const Restoration({required this.userId, this.createdAt, this.geohash});

  factory Restoration.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Restoration(
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
