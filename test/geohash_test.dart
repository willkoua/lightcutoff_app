import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/utils/geohash.dart';

void main() {
  group('encodeGeohash', () {
    test('vecteur de référence (Wikipédia)', () {
      // 57.64911, 10.40744 -> "u4pruydqqvj" (exemple canonique).
      expect(encodeGeohash(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
    });

    test('respecte la précision demandée', () {
      expect(encodeGeohash(3.848, 11.502, precision: 6).length, 6);
      expect(encodeGeohash(3.848, 11.502, precision: 9).length, 9);
    });

    test('déterministe', () {
      expect(
        encodeGeohash(3.848, 11.502),
        encodeGeohash(3.848, 11.502),
      );
    });

    test('un préfixe plus court est partagé par les positions proches', () {
      // Deux points très proches (~quelques mètres) partagent un long préfixe.
      final a = encodeGeohash(3.84800, 11.50200, precision: 7);
      final b = encodeGeohash(3.84805, 11.50205, precision: 7);
      expect(a.substring(0, 5), b.substring(0, 5));
    });

    test('des zones éloignées ne partagent pas le premier caractère', () {
      final yaounde = encodeGeohash(3.848, 11.502); // Cameroun
      final paris = encodeGeohash(48.8566, 2.3522); // France
      expect(yaounde[0], isNot(paris[0]));
    });
  });
}
