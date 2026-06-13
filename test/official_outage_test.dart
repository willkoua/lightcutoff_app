import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/official_outage.dart';
import 'package:lightcutoff_app/providers/official_outage_provider.dart';
import 'package:lightcutoff_app/repositories/official_outage_repository.dart';
import 'package:lightcutoff_app/services/official_outage_service.dart';

class _FakeRepo implements OfficialOutageRepository {
  _FakeRepo(this.items);
  final List<OfficialOutage> items;
  @override
  Future<List<OfficialOutage>> fetchUpcoming({required String country}) async =>
      items;
}

OfficialOutage _mk({
  String region = 'LITTORAL',
  String ville = 'DOUALA',
  String quartier = 'CITE SIC',
}) => OfficialOutage(
  id: '$region-$quartier',
  region: region,
  ville: ville,
  quartier: quartier,
);

void main() {
  group('OfficialOutage.fromDoc', () {
    test('parse les champs et les Timestamp', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('official_outages').doc('x1').set({
        'provider': 'eneo',
        'country': 'CM',
        'region': 'LITTORAL',
        'ville': 'DOUALA',
        'quartier': 'CITE SIC',
        'reason': 'Maintenance',
        'progDate': '2026-06-10',
        'startTime': '06:00',
        'endTime': '18:00',
        'startsAt': Timestamp.fromDate(DateTime.utc(2026, 6, 10, 5)),
      });
      final doc = await fake.collection('official_outages').doc('x1').get();
      final o = OfficialOutage.fromDoc(doc);
      expect(o.id, 'x1');
      expect(o.provider, 'eneo');
      expect(o.quartier, 'CITE SIC');
      expect(o.startTime, '06:00');
      // `Timestamp.toDate()` renvoie un DateTime local → on compare l'instant.
      expect(o.startsAt!.isAtSameMomentAs(DateTime.utc(2026, 6, 10, 5)), isTrue);
    });

    test('champs absents → valeurs par défaut sûres', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('official_outages').doc('x2').set({});
      final doc = await fake.collection('official_outages').doc('x2').get();
      final o = OfficialOutage.fromDoc(doc);
      expect(o.quartier, '');
      expect(o.startsAt, isNull);
    });
  });

  group('OfficialOutageService.fetchUpcoming', () {
    test('ne renvoie que les dates ≥ aujourd\'hui, triées', () async {
      final fake = FakeFirebaseFirestore();
      final col = fake.collection('official_outages');
      await col.doc('past').set(
        {'country': 'CM', 'quartier': 'OLD', 'progDate': '2000-01-01'},
      );
      await col.doc('future').set(
        {'country': 'CM', 'quartier': 'NEW', 'progDate': '2099-12-31'},
      );
      final service = OfficialOutageService(firestore: fake);

      final list = await service.fetchUpcoming(country: 'CM');

      expect(list.length, 1);
      expect(list.first.quartier, 'NEW');
    });
  });

  group('OfficialOutageProvider', () {
    test('charge la donnée et expose les régions distinctes triées', () async {
      final p = OfficialOutageProvider(
        country: 'CM',
        repository: _FakeRepo([
          _mk(region: 'LITTORAL'),
          _mk(region: 'CENTRE', quartier: 'BASTOS'),
          _mk(region: 'LITTORAL', quartier: 'BONABERI'),
        ]),
      );
      await p.load();
      expect(p.loading, isFalse);
      expect(p.regions, ['CENTRE', 'LITTORAL']);
    });

    test('filtre par région et recherche quartier', () async {
      final p = OfficialOutageProvider(
        country: 'CM',
        repository: _FakeRepo([
          _mk(region: 'LITTORAL', quartier: 'CITE SIC'),
          _mk(region: 'CENTRE', quartier: 'BASTOS'),
        ]),
      );
      await p.load();

      p.setRegion('CENTRE');
      expect(p.filtered.map((o) => o.quartier), ['BASTOS']);

      p.setRegion(null);
      p.setQuery('cite');
      expect(p.filtered.map((o) => o.quartier), ['CITE SIC']);
    });
  });
}
