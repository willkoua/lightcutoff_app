import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:lightcutoff_app/utils/outage_geocode.dart';

void main() {
  group('parseOutageStreets', () {
    test('découpe les rues et retire le bruit', () {
      final out = parseOutageStreets(
        'Kandara Road, Gichugu Road, Othaya Road, Laikipia Road & environs',
      );
      expect(out, ['Kandara Road', 'Gichugu Road', 'Othaya Road', 'Laikipia Road']);
    });

    test('retire « & adjacent customers » et la ponctuation finale', () {
      final out = parseOutageStreets(
        'Ruai Shopping Centre, Mawe Mbili, Stage 26 & adjacent customers.',
      );
      expect(out, ['Ruai Shopping Centre', 'Mawe Mbili', 'Stage 26']);
    });

    test('nettoie les préfixes vagues et dédoublonne', () {
      final out = parseOutageStreets('parts of Kawangware, Kawangware, environs');
      expect(out, ['Kawangware']);
    });

    test('borne le nombre de rues', () {
      final many = List.generate(30, (i) => 'Road $i').join(', ');
      expect(parseOutageStreets(many).length, kOutageMaxStreets);
    });

    test('description vide → liste vide', () {
      expect(parseOutageStreets('  '), isEmpty);
    });
  });

  group('boundingRadiusM', () {
    final center = const LatLng(-1.28, 36.79);

    test('borne basse quand les points sont très proches', () {
      final r = boundingRadiusM(center, [const LatLng(-1.2801, 36.7901)]);
      expect(r, kOutageZoneMinRadiusM);
    });

    test('borne haute quand un point est très loin', () {
      final r = boundingRadiusM(center, [const LatLng(-1.45, 36.95)]);
      expect(r, kOutageZoneMaxRadiusM);
    });
  });
}
