import 'package:cloud_firestore/cloud_firestore.dart';
import 'enums.dart';
import 'geo.dart';

class Report {
  final String id;
  final String userId;
  final OutageStatus status;
  final OutageType type;
  final GeoPosition position;
  final GeoArea location;
  final String? description;
  final String? mediaUrl;

  /// Pseudo de l'auteur, dénormalisé à la création (immuable côté pseudo).
  /// Sert d'attribution publique `@pseudo` ; le prénom/nom restent privés.
  final String? authorUsername;

  /// Geohash de [position] — index de proximité (filtres de zone, notifications).
  final String? geohash;

  /// Bounding box de l'**emprise mesurée** de la coupure : l'enveloppe des
  /// positions (centres de cellule geohash) des confirmeurs, maintenue côté
  /// serveur par la Cloud Function `onConfirmationCreated`. La carte en dérive
  /// un cercle (centre + rayon). `null` tant qu'aucune confirmation géolocalisée
  /// n'est arrivée → la carte retombe sur [position] avec un rayon plancher.
  final double? impactMinLat;
  final double? impactMaxLat;
  final double? impactMinLng;
  final double? impactMaxLng;

  final int confirmationCount;

  /// Nombre de déclarations « le courant est revenu chez moi ». Quand ce
  /// compteur franchit le seuil (cf. constantes), la Cloud Function
  /// [onRestorationCreated] passe le `status` à `resolved` automatiquement.
  final int restorationCount;
  final DateTime? reportedAt;
  final DateTime? resolvedAt;

  /// Horodatage de l'archivage par l'auteur. Quand non-`null`, le report est
  /// **invisible** côté app (filtré des listes / map / proximité / notifs) et
  /// sera purgé définitivement par le cron `purgeArchivedReports` au bout de
  /// [AppConstants.archivedRetentionDays] jours.
  final DateTime? archivedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Report({
    required this.id,
    required this.userId,
    required this.status,
    this.type = OutageType.unplanned,
    required this.position,
    this.location = const GeoArea(),
    this.description,
    this.mediaUrl,
    this.authorUsername,
    this.geohash,
    this.impactMinLat,
    this.impactMaxLat,
    this.impactMinLng,
    this.impactMaxLng,
    this.confirmationCount = 0,
    this.restorationCount = 0,
    this.reportedAt,
    this.resolvedAt,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Report.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Report(
      id: doc.id,
      userId: map['userId'] as String? ?? '',
      status: OutageStatus.fromName(map['status'] as String?),
      type: OutageType.fromName(map['type'] as String?),
      position: GeoPosition.fromMap(
        (map['position'] as Map<String, dynamic>?) ?? const {},
      ),
      location: GeoArea.fromMap(map['location'] as Map<String, dynamic>?),
      description: map['description'] as String?,
      mediaUrl: map['mediaUrl'] as String?,
      authorUsername: map['authorUsername'] as String?,
      geohash: map['geohash'] as String?,
      impactMinLat: (map['impactMinLat'] as num?)?.toDouble(),
      impactMaxLat: (map['impactMaxLat'] as num?)?.toDouble(),
      impactMinLng: (map['impactMinLng'] as num?)?.toDouble(),
      impactMaxLng: (map['impactMaxLng'] as num?)?.toDouble(),
      confirmationCount: (map['confirmationCount'] as num?)?.toInt() ?? 0,
      restorationCount: (map['restorationCount'] as num?)?.toInt() ?? 0,
      reportedAt: (map['reportedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (map['resolvedAt'] as Timestamp?)?.toDate(),
      archivedAt: (map['archivedAt'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Données pour la création d'un signalement.
  Map<String, dynamic> toCreateMap() => {
    'userId': userId,
    'status': status.name,
    'type': type.name,
    'position': position.toMap(),
    'location': location.toMap(),
    'description': description,
    'mediaUrl': mediaUrl,
    'authorUsername': authorUsername,
    'geohash': geohash,
    'confirmationCount': 0,
    'restorationCount': 0,
    'reportedAt':
        reportedAt != null
            ? Timestamp.fromDate(reportedAt!)
            : FieldValue.serverTimestamp(),
    'resolvedAt': null,
    'archivedAt': null,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
