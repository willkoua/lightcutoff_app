import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/confirmation.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../repositories/report_repository.dart';
import '../utils/geohash.dart';

/// Implémentation Firestore de [ReportRepository].
class ReportService implements ReportRepository {
  ReportService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection('reports');

  /// Flux des coupures, les plus récentes d'abord.
  @override
  Stream<List<Report>> watchReports({int limit = 50}) {
    return _reports
        .orderBy('reportedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Report.fromDoc).toList());
  }

  @override
  Future<List<Report>> reportsWithinRadius({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    // 1) Pré-sélection serveur : une requête de plage par cellule couvrante.
    final prefixes = geohashesCovering(lat, lng, radiusMeters);
    final found = <String, Report>{};
    await Future.wait(
      prefixes.map((p) async {
        final snap =
            await _reports
                .where('geohash', isGreaterThanOrEqualTo: p)
                .where('geohash', isLessThanOrEqualTo: '$p~')
                .get();
        for (final d in snap.docs) {
          found[d.id] = Report.fromDoc(d);
        }
      }),
    );

    // 2) Affinage client : distance exacte (cellule = carré, rayon = cercle).
    const distance = Distance();
    final center = LatLng(lat, lng);
    return found.values.where((r) {
      final d = distance.as(
        LengthUnit.Meter,
        center,
        LatLng(r.position.lat, r.position.lng),
      );
      return d <= radiusMeters;
    }).toList();
  }

  @override
  Future<void> createReport(Report report) {
    return _reports.add(report.toCreateMap());
  }

  /// Marque une coupure comme rétablie (réservé à l'auteur par les règles).
  @override
  Future<void> resolveReport(String reportId) {
    return _reports.doc(reportId).update({
      'status': OutageStatus.resolved.name,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Flux des confirmations d'une coupure, les plus récentes d'abord.
  @override
  Stream<List<Confirmation>> watchConfirmations(String reportId) {
    return _reports
        .doc(reportId)
        .collection('confirmations')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Confirmation.fromDoc).toList());
  }

  @override
  Future<bool> hasConfirmed(String reportId, String uid) async {
    final doc =
        await _reports.doc(reportId).collection('confirmations').doc(uid).get();
    return doc.exists;
  }

  /// Confirme une coupure : un vote unique par utilisateur, compteur incrémenté
  /// de façon atomique. Sans effet si l'utilisateur a déjà confirmé.
  @override
  Future<void> confirmReport(String reportId, String uid) {
    final reportRef = _reports.doc(reportId);
    final confRef = reportRef.collection('confirmations').doc(uid);
    return _db.runTransaction((tx) async {
      final existing = await tx.get(confRef);
      if (existing.exists) return;
      tx.set(confRef, {'createdAt': FieldValue.serverTimestamp()});
      tx.update(reportRef, {
        'confirmationCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
