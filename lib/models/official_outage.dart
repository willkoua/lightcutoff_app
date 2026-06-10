import 'package:cloud_firestore/cloud_firestore.dart';

/// Coupure **officielle planifiée** importée d'un fournisseur (Eneo aujourd'hui),
/// lue depuis la collection Firestore `official_outages` (alimentée côté serveur).
/// Couche distincte des signalements communautaires (`Report`).
class OfficialOutage {
  final String id;
  final String provider; // ex. "eneo"
  final String country;
  final String region;
  final String ville;
  final String quartier;
  final String reason; // motif des travaux
  final String progDate; // YYYY-MM-DD (date locale du fournisseur)
  final String startTime; // HH:MM locale (affichage)
  final String endTime;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const OfficialOutage({
    required this.id,
    this.provider = '',
    this.country = '',
    this.region = '',
    this.ville = '',
    this.quartier = '',
    this.reason = '',
    this.progDate = '',
    this.startTime = '',
    this.endTime = '',
    this.startsAt,
    this.endsAt,
  });

  /// Clé de suivi d'un quartier (alignée avec la Cloud Function d'alerte).
  String get followKey => '$region|$ville|$quartier';

  factory OfficialOutage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return OfficialOutage(
      id: doc.id,
      provider: map['provider'] as String? ?? '',
      country: map['country'] as String? ?? '',
      region: map['region'] as String? ?? '',
      ville: map['ville'] as String? ?? '',
      quartier: map['quartier'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      progDate: map['progDate'] as String? ?? '',
      startTime: map['startTime'] as String? ?? '',
      endTime: map['endTime'] as String? ?? '',
      startsAt: (map['startsAt'] as Timestamp?)?.toDate(),
      endsAt: (map['endsAt'] as Timestamp?)?.toDate(),
    );
  }
}
