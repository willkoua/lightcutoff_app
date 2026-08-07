import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/utils/impact_zone.dart';

void main() {
  group('zoneRadiusM', () {
    test('plancher pour les reports jamais confirmés (null ou trop petit)', () {
      expect(zoneRadiusM(null), kImpactMinRadiusM);
      expect(zoneRadiusM(40), kImpactMinRadiusM);
    });

    test("suit l'agrégat serveur au-delà du plancher", () {
      expect(zoneRadiusM(480), 480);
      expect(zoneRadiusM(2000), 2000);
    });
  });

  group('zoneOpacity', () {
    final now = DateTime(2026, 8, 7, 12);

    test('signal frais (< 2 h) -> opacité max', () {
      expect(zoneOpacity(now, now: now), kZoneMaxOpacity);
      expect(
        zoneOpacity(now.subtract(const Duration(hours: 1)), now: now),
        kZoneMaxOpacity,
      );
    });

    test('signal ancien (>= 24 h) ou inconnu -> opacité min', () {
      expect(
        zoneOpacity(now.subtract(const Duration(hours: 24)), now: now),
        kZoneMinOpacity,
      );
      expect(
        zoneOpacity(now.subtract(const Duration(days: 3)), now: now),
        kZoneMinOpacity,
      );
      expect(zoneOpacity(null, now: now), kZoneMinOpacity);
    });

    test('décroissance monotone entre 2 h et 24 h', () {
      final at6h = zoneOpacity(
        now.subtract(const Duration(hours: 6)),
        now: now,
      );
      final at18h = zoneOpacity(
        now.subtract(const Duration(hours: 18)),
        now: now,
      );
      expect(at6h, lessThan(kZoneMaxOpacity));
      expect(at6h, greaterThan(at18h));
      expect(at18h, greaterThan(kZoneMinOpacity));
    });
  });

  group('zoneBorderOpacity', () {
    test('double le remplissage, plafonné à 0.6', () {
      expect(zoneBorderOpacity(0.1), closeTo(0.2, 1e-9));
      expect(zoneBorderOpacity(0.28), closeTo(0.56, 1e-9));
      expect(zoneBorderOpacity(0.4), 0.6);
    });
  });
}
