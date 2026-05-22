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

  group('geohashNeighbors', () {
    test('renvoie 8 voisines distinctes, de même longueur, ≠ centre', () {
      const center = 's28jyn';
      final ns = geohashNeighbors(center);
      expect(ns, hasLength(8));
      expect(ns.toSet(), hasLength(8)); // toutes distinctes
      expect(ns, everyElement(hasLength(center.length)));
      expect(ns, isNot(contains(center)));
    });

    test('aller-retour : ouest(est(x)) == x (et n/s)', () {
      for (final h in ['s28jyn', 'u4pruyd', 'gbsuv']) {
        final e = geohashNeighbors(h)[2]; // est
        final w = geohashNeighbors(h)[3]; // ouest
        expect(geohashNeighbors(e)[3], h); // ouest de l'est = centre
        expect(geohashNeighbors(w)[2], h); // est de l'ouest = centre
      }
    });
  });

  group('geohashesCovering', () {
    test('centre + 8 voisines = 9 préfixes uniques', () {
      final cover = geohashesCovering(3.861, 11.515, 2000);
      expect(cover, hasLength(9));
      expect(cover.toSet(), hasLength(9));
    });

    test('précision adaptée au rayon', () {
      expect(geohashPrecisionForRadius(2000), 5); // 2 km -> cellule ~4,9 km
      expect(geohashPrecisionForRadius(5000), 4); // 5 km -> cellule ~19,5 km
      expect(geohashesCovering(3.861, 11.515, 2000).first.length, 5);
    });

    test('le centre couvre bien la position demandée', () {
      final cover = geohashesCovering(3.861, 11.515, 2000);
      expect(cover.first, encodeGeohash(3.861, 11.515, precision: 5));
    });
  });
}
