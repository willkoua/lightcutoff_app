import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/device.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/services/device_service.dart';

/// Tests d'intégration de [DeviceService] contre un Firestore fake.
/// Vérifie l'upsert idempotent (id du doc = token, merge), la suppression et
/// la lecture de `fcmEnabled`.
void main() {
  late FakeFirebaseFirestore fake;
  late DeviceService service;

  setUp(() {
    fake = FakeFirebaseFirestore();
    service = DeviceService(db: fake);
  });

  Device device({String token = 'tok-1', bool? fcm}) => Device(
    token: token,
    userId: 'u1',
    platform: 'android',
    homeLocation: const GeoArea(city: 'Yaoundé'),
    geohash: 's2x9c',
    fcmEnabled: fcm ?? true,
  );

  test('upsertDevice écrit sous l\'id = token, sans dupliquer le token', () async {
    await service.upsertDevice(device(token: 'abc'));

    final doc = await fake.collection('devices').doc('abc').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['userId'], 'u1');
    expect(doc.data()!['platform'], 'android');
    expect(doc.data()!.containsKey('token'), isFalse); // token = id, pas un champ
  });

  test('upsert idempotent : un seul doc par token', () async {
    await service.upsertDevice(device(token: 'abc'));
    await service.upsertDevice(device(token: 'abc'));

    final all = await fake.collection('devices').get();
    expect(all.size, 1);
  });

  test('getFcmEnabled lit la valeur, null si device absent', () async {
    expect(await service.getFcmEnabled('absent'), isNull);

    await service.upsertDevice(device(token: 'abc', fcm: false));
    expect(await service.getFcmEnabled('abc'), isFalse);
  });

  test('deleteDevice supprime le doc', () async {
    await service.upsertDevice(device(token: 'abc'));
    await service.deleteDevice('abc');

    final doc = await fake.collection('devices').doc('abc').get();
    expect(doc.exists, isFalse);
  });
}
