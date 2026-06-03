import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/confirmation.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../models/restoration.dart';
import '../repositories/report_repository.dart';
import '../utils/geohash.dart';

/// Implémentation Firestore de [ReportRepository].
class ReportService implements ReportRepository {
  ReportService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection('reports');

  /// Flux des coupures, les plus récentes d'abord. Filtre les reports
  /// archivés côté client (évite un index composite Firestore — acceptable
  /// au volume MVP, car les archivages sont rares).
  @override
  Stream<List<Report>> watchReports({int limit = 50}) {
    return _reports
        .orderBy('reportedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) =>
              snap.docs
                  .map(Report.fromDoc)
                  .where((r) => r.archivedAt == null)
                  .toList(),
        );
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

    // 2) Affinage client : distance exacte (cellule = carré, rayon = cercle)
    // et exclusion des reports archivés.
    const distance = Distance();
    final center = LatLng(lat, lng);
    return found.values.where((r) {
      if (r.archivedAt != null) return false;
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

  /// Soft-delete : pose `archivedAt = now`. La règle Firestore vérifie que
  /// l'auteur seul peut écrire ce champ. Hard delete différé au cron.
  @override
  Future<void> archiveReport(String reportId) {
    return _reports.doc(reportId).update({
      'archivedAt': FieldValue.serverTimestamp(),
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

  @override
  Stream<List<Restoration>> watchRestorations(String reportId) {
    return _reports
        .doc(reportId)
        .collection('restorations')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Restoration.fromDoc).toList());
  }

  @override
  Future<bool> hasRestored(String reportId, String uid) async {
    final doc =
        await _reports.doc(reportId).collection('restorations').doc(uid).get();
    return doc.exists;
  }

  /// Déclare le rétablissement chez [uid] : vote unique par utilisateur,
  /// compteur incrémenté de façon atomique. L'auto-résolution (passage du
  /// status à `resolved`) est portée par la Cloud Function
  /// [onRestorationCreated] côté serveur — pas ici, pour éviter les
  /// conditions de course entre clients.
  @override
  Future<void> markRestored(String reportId, String uid) {
    final reportRef = _reports.doc(reportId);
    final restoRef = reportRef.collection('restorations').doc(uid);
    return _db.runTransaction((tx) async {
      final existing = await tx.get(restoRef);
      if (existing.exists) return;
      tx.set(restoRef, {'createdAt': FieldValue.serverTimestamp()});
      tx.update(reportRef, {
        'restorationCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
