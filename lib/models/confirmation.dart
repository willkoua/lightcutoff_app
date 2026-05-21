import 'package:cloud_firestore/cloud_firestore.dart';

/// Confirmation d'une coupure existante par un utilisateur.
/// Stockée dans la sous-collection `reports/{reportId}/confirmations/{uid}`,
/// l'id du document étant l'uid (un seul vote par utilisateur).
class Confirmation {
  final String userId;
  final DateTime? createdAt;

  const Confirmation({required this.userId, this.createdAt});

  factory Confirmation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Confirmation(
      userId: doc.id,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'createdAt': FieldValue.serverTimestamp(),
  };
}
