import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/services/report_service.dart';
import 'package:lightcutoff_app/utils/geohash.dart';

/// Tests d'intégration de [ReportService] contre un Firestore **fake**
/// en mémoire (`fake_cloud_firestore`). Exercent la vraie logique —
/// transactions de vote unique, increments atomiques, requêtes de plage
/// geohash, filtrage des archivés — sans appareil ni émulateur (CI-friendly).
void main() {
  late FakeFirebaseFirestore fake;
  late ReportService service;

  setUp(() {
    fake = FakeFirebaseFirestore();
    service = ReportService(firestore: fake);
  });

  Future<void> seedReport(
    String id, {
    String geohash = '',
    double lat = 0,
    double lng = 0,
    int confirmations = 0,
    int restorations = 0,
    DateTime? reportedAt,
    DateTime? archivedAt,
    String status = 'ongoing',
  }) {
    return fake.collection('reports').doc(id).set({
      'userId': 'author',
      'status': status,
      'type': 'unplanned',
      'position': {'lat': lat, 'lng': lng},
      'location': {'city': 'Yaoundé'},
      'geohash': geohash,
      'confirmationCount': confirmations,
      'restorationCount': restorations,
      'reportedAt': Timestamp.fromDate(reportedAt ?? DateTime(2024, 1, 1)),
      'archivedAt': archivedAt == null ? null : Timestamp.fromDate(archivedAt),
    });
  }

  test('createReport persiste le report avec compteurs à 0', () async {
    await service.createReport(
      const Report(
        id: '',
        userId: 'u1',
        status: OutageStatus.ongoing,
        position: GeoPosition(lat: 1, lng: 2),
        geohash: 's2x9c',
      ),
    );
    final docs = await fake.collection('reports').get();
    expect(docs.size, 1);
    final data = docs.docs.first.data();
    expect(data['userId'], 'u1');
    expect(data['confirmationCount'], 0);
    expect(data['restorationCount'], 0);
    expect(data['geohash'], 's2x9c');
  });

  group('watchReport (repli détail hors liste)', () {
    test('émet le report quand il existe', () async {
      await seedReport('r1', confirmations: 2);
      final r = await service.watchReport('r1').first;
      expect(r, isNotNull);
      expect(r!.id, 'r1');
      expect(r.confirmationCount, 2);
    });

    test('émet null quand le report n\'existe pas', () async {
      final r = await service.watchReport('absent').first;
      expect(r, isNull);
    });

    test('émet null quand le report est archivé (invisible)', () async {
      await seedReport('r1', archivedAt: DateTime(2024, 2, 1));
      final r = await service.watchReport('r1').first;
      expect(r, isNull);
    });
  });

  group('confirmReport (transaction, vote unique)', () {
    test('incrémente une seule fois pour un même utilisateur', () async {
      await seedReport('r1');
      await service.confirmReport('r1', 'voter');
      await service.confirmReport('r1', 'voter'); // re-vote : sans effet

      final doc = await fake.collection('reports').doc('r1').get();
      expect(doc.data()!['confirmationCount'], 1);
      expect(await service.hasConfirmed('r1', 'voter'), isTrue);
      expect(await service.hasConfirmed('r1', 'autre'), isFalse);
    });

    test('des votants distincts cumulent', () async {
      await seedReport('r1');
      await service.confirmReport('r1', 'a');
      await service.confirmReport('r1', 'b');

      final doc = await fake.collection('reports').doc('r1').get();
      expect(doc.data()!['confirmationCount'], 2);
    });
  });

  group('denyReport (« pas chez moi », signal négatif)', () {
    test('écrit le doc denials/{uid} SANS toucher aux compteurs', () async {
      await seedReport('r1');
      await service.denyReport('r1', 'u', geohash: 's2x9c', lat: 3.8, lng: 11.5);

      final report = await fake.collection('reports').doc('r1').get();
      expect(report.data()!['confirmationCount'], 0); // aucun compteur bougé
      expect(report.data()!['restorationCount'], 0);

      final denial =
          await fake
              .collection('reports')
              .doc('r1')
              .collection('denials')
              .doc('u')
              .get();
      expect(denial.exists, isTrue);
      expect(denial.data()!['geohash'], 's2x9c');
      expect(denial.data()!['position'], {'lat': 3.8, 'lng': 11.5});
      expect(await service.hasDenied('r1', 'u'), isTrue);
      expect(await service.hasDenied('r1', 'autre'), isFalse);
    });

    test('idempotent : un seul doc par utilisateur', () async {
      await seedReport('r1');
      await service.denyReport('r1', 'u');
      await service.denyReport('r1', 'u');

      final denials =
          await fake
              .collection('reports')
              .doc('r1')
              .collection('denials')
              .get();
      expect(denials.size, 1);
    });
  });

  group('markRestored (transaction, vote unique)', () {
    test('incrémente restorationCount et écrit la sous-collection', () async {
      await seedReport('r1');
      await service.markRestored('r1', 'u');
      await service.markRestored('r1', 'u'); // sans effet

      final doc = await fake.collection('reports').doc('r1').get();
      expect(doc.data()!['restorationCount'], 1);
      expect(await service.hasRestored('r1', 'u'), isTrue);
    });
  });

  group('watchReports', () {
    test('exclut les archivés et ordonne par date décroissante', () async {
      await seedReport('r1', reportedAt: DateTime(2024, 1, 1));
      await seedReport('r2', reportedAt: DateTime(2024, 1, 2));
      await seedReport(
        'old',
        reportedAt: DateTime(2024, 1, 3),
        archivedAt: DateTime(2024, 6, 1),
      );

      final list = await service.watchReports(limit: 10).first;
      expect(list.map((r) => r.id), ['r2', 'r1']); // 'old' archivé filtré
    });
  });

  group('archiveReport', () {
    test('pose archivedAt → le report disparaît du flux', () async {
      await seedReport('r1');
      await service.archiveReport('r1');

      final doc = await fake.collection('reports').doc('r1').get();
      expect(doc.data()!['archivedAt'], isNotNull);

      final list = await service.watchReports(limit: 10).first;
      expect(list, isEmpty);
    });
  });

  group('reportsWithinRadius (couverture geohash + distance)', () {
    const lat = 3.848, lng = 11.502; // Yaoundé

    test('retourne les coupures proches, exclut les lointaines', () async {
      await seedReport(
        'near',
        geohash: encodeGeohash(lat, lng),
        lat: lat,
        lng: lng,
      );
      await seedReport(
        'far',
        geohash: encodeGeohash(48.8566, 2.3522), // Paris
        lat: 48.8566,
        lng: 2.3522,
      );

      final res = await service.reportsWithinRadius(
        lat: lat,
        lng: lng,
        radiusMeters: 5000,
      );
      expect(res.map((r) => r.id), ['near']);
    });

    test('exclut les archivés même proches', () async {
      await seedReport(
        'arch',
        geohash: encodeGeohash(lat, lng),
        lat: lat,
        lng: lng,
        archivedAt: DateTime(2024, 6, 1),
      );

      final res = await service.reportsWithinRadius(
        lat: lat,
        lng: lng,
        radiusMeters: 5000,
      );
      expect(res, isEmpty);
    });
  });
}
