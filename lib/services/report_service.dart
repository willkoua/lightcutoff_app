import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/enums.dart';
import '../models/report.dart';

class ReportService {
  ReportService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection('reports');

  /// Flux des coupures, les plus récentes d'abord.
  Stream<List<Report>> watchReports({int limit = 50}) {
    return _reports
        .orderBy('reportedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Report.fromDoc).toList());
  }

  Future<void> createReport(Report report) {
    return _reports.add(report.toCreateMap());
  }

  /// Marque une coupure comme rétablie (réservé à l'auteur par les règles).
  Future<void> resolveReport(String reportId) {
    return _reports.doc(reportId).update({
      'status': OutageStatus.resolved.name,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> hasConfirmed(String reportId, String uid) async {
    final doc =
        await _reports.doc(reportId).collection('confirmations').doc(uid).get();
    return doc.exists;
  }

  /// Confirme une coupure : un vote unique par utilisateur, compteur incrémenté
  /// de façon atomique. Sans effet si l'utilisateur a déjà confirmé.
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
