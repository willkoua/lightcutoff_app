import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/app_user.dart';
import 'package:lightcutoff_app/models/device.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/models/restoration.dart';

void main() {
  group('Enums.fromName', () {
    test('valeurs connues', () {
      expect(UserRole.fromName('operator'), UserRole.operator);
      expect(AccountStatus.fromName('disabled'), AccountStatus.disabled);
      expect(OutageStatus.fromName('resolved'), OutageStatus.resolved);
      expect(OutageType.fromName('scheduled'), OutageType.scheduled);
    });

    test('valeurs inconnues ou nulles -> défaut', () {
      expect(UserRole.fromName(null), UserRole.citizen);
      expect(AccountStatus.fromName('???'), AccountStatus.active);
      expect(OutageStatus.fromName(null), OutageStatus.ongoing);
      expect(OutageType.fromName('xyz'), OutageType.unplanned);
    });
  });

  group('Libellés FR', () {
    test('statut', () {
      expect(OutageStatus.ongoing.label, 'En cours');
      expect(OutageStatus.resolved.label, 'Rétabli');
    });

    test('type', () {
      expect(OutageType.unplanned.label, 'Coupure imprévue');
      expect(OutageType.scheduled.label, 'Coupure programmée');
    });
  });

  group('GeoPosition', () {
    test('fromMap / toMap', () {
      final p = GeoPosition.fromMap({'lat': 3.848, 'lng': 11.502});
      expect(p.lat, 3.848);
      expect(p.lng, 11.502);
      expect(p.toMap(), {'lat': 3.848, 'lng': 11.502});
    });

    test('valeurs manquantes -> 0', () {
      final p = GeoPosition.fromMap({});
      expect(p.lat, 0);
      expect(p.lng, 0);
    });
  });

  group('GeoArea', () {
    test('label ignore les champs vides', () {
      const area = GeoArea(city: 'Yaoundé', country: 'Cameroun');
      expect(area.label, 'Yaoundé, Cameroun');
    });

    test('label complet dans l\'ordre quartier→pays', () {
      const area = GeoArea(
        neighborhood: 'Bastos',
        city: 'Yaoundé',
        region: 'Centre',
        country: 'Cameroun',
      );
      expect(area.label, 'Bastos, Yaoundé, Centre, Cameroun');
    });

    test('fromMap null -> vide', () {
      final area = GeoArea.fromMap(null);
      expect(area.label, '');
    });
  });

  group('Report.toCreateMap', () {
    test('sérialise les champs métier', () {
      const report = Report(
        id: '',
        userId: 'u1',
        status: OutageStatus.ongoing,
        type: OutageType.scheduled,
        position: GeoPosition(lat: 1, lng: 2),
        location: GeoArea(city: 'Douala'),
        description: 'test',
        authorUsername: 'willk',
      );
      final map = report.toCreateMap();
      expect(map['userId'], 'u1');
      expect(map['status'], 'ongoing');
      expect(map['type'], 'scheduled');
      expect(map['position'], {'lat': 1.0, 'lng': 2.0});
      expect((map['location'] as Map)['city'], 'Douala');
      expect(map['description'], 'test');
      expect(map['authorUsername'], 'willk');
      expect(map['confirmationCount'], 0);
      expect(map['restorationCount'], 0);
      expect(map['resolvedAt'], isNull);
    });
  });

  group('Restoration', () {
    test('toCreateMap pose un createdAt serveur', () {
      const r = Restoration(userId: 'bob');
      final map = r.toCreateMap();
      expect(map.containsKey('createdAt'), isTrue);
    });
  });

  group('Device.toWriteMap', () {
    test('sérialise les champs et n\'inclut pas le token (= id du doc)', () {
      const device = Device(
        token: 'tok-123',
        userId: 'u1',
        platform: 'android',
        homeLocation: GeoArea(city: 'Yaoundé'),
        geohash: 's2x9c',
      );
      final map = device.toWriteMap();
      expect(map['userId'], 'u1');
      expect(map['platform'], 'android');
      expect((map['homeLocation'] as Map)['city'], 'Yaoundé');
      expect(map['geohash'], 's2x9c');
      expect(map['fcmEnabled'], true);
      expect(map.containsKey('token'), isFalse);
    });
  });

  group('AppUser', () {
    test('fullName combine prénom et nom', () {
      const u = AppUser(
        uid: 'u1',
        email: 'a@b.com',
        firstName: 'Willy',
        lastName: 'Kouagnia',
      );
      expect(u.fullName, 'Willy Kouagnia');
    });

    test('toCreateMap sérialise les nouveaux champs', () {
      final u = AppUser(
        uid: 'u1',
        email: 'a@b.com',
        username: 'willk',
        firstName: 'Willy',
        lastName: 'Kouagnia',
        birthDate: DateTime(2000, 1, 2),
      );
      final map = u.toCreateMap();
      expect(map['username'], 'willk');
      expect(map['firstName'], 'Willy');
      expect(map['lastName'], 'Kouagnia');
      expect(map['birthDate'], isNotNull);
      expect(map['role'], 'citizen');
    });
  });
}
