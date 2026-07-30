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
  Stream<List<Report>> watchReports({int limit = 50, String? countryCode}) {
    // Cloisonnement pays **côté serveur** : quand un pays est fourni, la
    // fenêtre `limit` porte sur CE pays uniquement (sinon les N récents du
    // monde entier pourraient saturer la fenêtre et masquer les coupures du
    // pays de l'utilisateur — cf. index composite location.countryCode +
    // reportedAt dans firestore.indexes.json). `null` = mode admin « monde ».
    Query<Map<String, dynamic>> q = _reports;
    if (countryCode != null && countryCode.isNotEmpty) {
      q = q.where('location.countryCode', isEqualTo: countryCode.toUpperCase());
    }
    return q
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
  Stream<Report?> watchReport(String reportId) {
    return _reports.doc(reportId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final r = Report.fromDoc(doc);
      // Un report archivé est invisible (cohérent avec le filtrage des listes).
      return r.archivedAt == null ? r : null;
    });
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

  /// Coupures d'un auteur (stats perso). Filtre `userId` = champ unique → pas
  /// d'index composite ; l'exclusion des archivés se fait côté client (rare).
  @override
  Future<List<Report>> reportsByAuthor(String uid) async {
    final snap = await _reports.where('userId', isEqualTo: uid).get();
    return snap.docs
        .map(Report.fromDoc)
        .where((r) => r.archivedAt == null)
        .toList();
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

  /// Soft-delete : pose `archivedAt = now` (+ `archiveReason` si fournie). La
  /// règle Firestore vérifie que l'auteur seul peut écrire ces champs. Hard
  /// delete différé au cron (actuellement désactivé).
  @override
  Future<void> archiveReport(String reportId, {String? reason}) {
    return _reports.doc(reportId).update({
      'archivedAt': FieldValue.serverTimestamp(),
      if (reason != null && reason.isNotEmpty) 'archiveReason': reason,
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

  /// « Pas de coupure chez moi » : un doc par utilisateur (`denials/{uid}`),
  /// idempotent (set). Ne touche aucun compteur du report — le signal sert à
  /// délimiter l'emprise de la coupure côté Cloud Functions / analyse.
  @override
  Future<void> denyReport(
    String reportId,
    String uid, {
    String? geohash,
    double? lat,
    double? lng,
  }) {
    return _reports.doc(reportId).collection('denials').doc(uid).set({
      'createdAt': FieldValue.serverTimestamp(),
      if (geohash != null) 'geohash': geohash,
      // Position exacte du répondant — même contrat que les confirmations :
      // lecture verrouillée (admin/owner), consommée par l'Admin SDK.
      if (lat != null && lng != null) 'position': {'lat': lat, 'lng': lng},
    });
  }

  @override
  Future<void> flagReport(
    String reportId,
    String uid, {
    required String reason,
    String? details,
  }) {
    return _reports.doc(reportId).collection('flags').doc(uid).set({
      'createdAt': FieldValue.serverTimestamp(),
      'reason': reason,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

  @override
  Future<bool> hasFlagged(String reportId, String uid) async {
    final doc = await _reports.doc(reportId).collection('flags').doc(uid).get();
    return doc.exists;
  }

  @override
  Future<bool> hasDenied(String reportId, String uid) async {
    final doc =
        await _reports.doc(reportId).collection('denials').doc(uid).get();
    return doc.exists;
  }

  /// Confirme une coupure : un vote unique par utilisateur, compteur incrémenté
  /// de façon atomique. Sans effet si l'utilisateur a déjà confirmé.
  @override
  Future<void> confirmReport(
    String reportId,
    String uid, {
    String? geohash,
    double? lat,
    double? lng,
  }) {
    final reportRef = _reports.doc(reportId);
    final confRef = reportRef.collection('confirmations').doc(uid);
    return _db.runTransaction((tx) async {
      final existing = await tx.get(confRef);
      if (existing.exists) return;
      tx.set(confRef, {
        'createdAt': FieldValue.serverTimestamp(),
        if (geohash != null) 'geohash': geohash,
        // Position exacte du confirmeur — sert au ciblage 500 m des
        // notifications (Cloud Function `onConfirmationCreated`, Admin SDK).
        // Lecture verrouillée aux règles (propriétaire + admin uniquement).
        if (lat != null && lng != null) 'position': {'lat': lat, 'lng': lng},
      });
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
  Future<void> markRestored(String reportId, String uid, {String? geohash}) {
    final reportRef = _reports.doc(reportId);
    final restoRef = reportRef.collection('restorations').doc(uid);
    return _db.runTransaction((tx) async {
      final existing = await tx.get(restoRef);
      if (existing.exists) return;
      tx.set(restoRef, {
        'createdAt': FieldValue.serverTimestamp(),
        if (geohash != null) 'geohash': geohash,
      });
      tx.update(reportRef, {
        'restorationCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
