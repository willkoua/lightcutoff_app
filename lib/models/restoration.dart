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

  const Restoration({required this.userId, this.createdAt});

  factory Restoration.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Restoration(
      userId: doc.id,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'createdAt': FieldValue.serverTimestamp(),
  };
}
