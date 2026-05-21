import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';
import 'geo.dart';

class Report {
  final String id;
  final String userId;
  final OutageStatus status;
  final OutageCause cause;
  final GeoPosition position;
  final GeoArea location;
  final String? description;
  final int confirmationCount;
  final DateTime? reportedAt;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Report({
    required this.id,
    required this.userId,
    required this.status,
    this.cause = OutageCause.unknown,
    required this.position,
    this.location = const GeoArea(),
    this.description,
    this.confirmationCount = 0,
    this.reportedAt,
    this.resolvedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Report.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Report(
      id: doc.id,
      userId: map['userId'] as String? ?? '',
      status: OutageStatus.fromName(map['status'] as String?),
      cause: OutageCause.fromName(map['cause'] as String?),
      position: GeoPosition.fromMap(
        (map['position'] as Map<String, dynamic>?) ?? const {},
      ),
      location: GeoArea.fromMap(map['location'] as Map<String, dynamic>?),
      description: map['description'] as String?,
      confirmationCount: (map['confirmationCount'] as num?)?.toInt() ?? 0,
      reportedAt: (map['reportedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (map['resolvedAt'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Données pour la création d'un signalement.
  Map<String, dynamic> toCreateMap() => {
        'userId': userId,
        'status': status.name,
        'cause': cause.name,
        'position': position.toMap(),
        'location': location.toMap(),
        'description': description,
        'confirmationCount': 0,
        'reportedAt': reportedAt != null
            ? Timestamp.fromDate(reportedAt!)
            : FieldValue.serverTimestamp(),
        'resolvedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
