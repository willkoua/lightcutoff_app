import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/utils/outage_stats.dart';

Report _report({
  OutageStatus status = OutageStatus.ongoing,
  DateTime? reportedAt,
  DateTime? resolvedAt,
}) {
  return Report(
    id: 'x',
    userId: 'u',
    status: status,
    position: const GeoPosition(lat: 0, lng: 0),
    reportedAt: reportedAt,
    resolvedAt: resolvedAt,
  );
}

void main() {
  group('computeOutageStats', () {
    test('liste vide → tout à zéro, isEmpty', () {
      final s = computeOutageStats([]);
      expect(s.isEmpty, isTrue);
      expect(s.total, 0);
      expect(s.resolvedCount, 0);
      expect(s.averageResolvedDuration, isNull);
      expect(s.peakHour, isNull);
      expect(s.peakWeekday, isNull);
    });

    test('durée comptée seulement pour les coupures rétablies', () {
      // 2024-01-01 = lundi, 08:00 → 10:00 (2 h) rétablie.
      final resolved = _report(
        status: OutageStatus.resolved,
        reportedAt: DateTime(2024, 1, 1, 8),
        resolvedAt: DateTime(2024, 1, 1, 10),
      );
      // En cours : ne compte pas dans la durée.
      final ongoing = _report(
        status: OutageStatus.ongoing,
        reportedAt: DateTime(2024, 1, 1, 9),
      );
      final s = computeOutageStats([resolved, ongoing]);
      expect(s.total, 2);
      expect(s.resolvedCount, 1);
      expect(s.ongoingCount, 1);
      expect(s.totalResolvedDuration, const Duration(hours: 2));
      expect(s.averageResolvedDuration, const Duration(hours: 2));
    });

    test('durée négative (données incohérentes) ignorée', () {
      final bad = _report(
        status: OutageStatus.resolved,
        reportedAt: DateTime(2024, 1, 1, 10),
        resolvedAt: DateTime(2024, 1, 1, 8), // avant le signalement
      );
      final s = computeOutageStats([bad]);
      expect(s.resolvedCount, 0);
      expect(s.totalResolvedDuration, Duration.zero);
      expect(s.averageResolvedDuration, isNull);
    });

    test('moyenne sur plusieurs coupures rétablies', () {
      final a = _report(
        status: OutageStatus.resolved,
        reportedAt: DateTime(2024, 1, 1, 8),
        resolvedAt: DateTime(2024, 1, 1, 10), // 2 h
      );
      final b = _report(
        status: OutageStatus.resolved,
        reportedAt: DateTime(2024, 1, 2, 8),
        resolvedAt: DateTime(2024, 1, 2, 12), // 4 h
      );
      final s = computeOutageStats([a, b]);
      expect(s.averageResolvedDuration, const Duration(hours: 3));
    });

    test('répartition par heure et pic horaire', () {
      final s = computeOutageStats([
        _report(reportedAt: DateTime(2024, 1, 1, 18)),
        _report(reportedAt: DateTime(2024, 1, 2, 18)),
        _report(reportedAt: DateTime(2024, 1, 3, 9)),
      ]);
      expect(s.byHour[18], 2);
      expect(s.byHour[9], 1);
      expect(s.peakHour, 18);
    });

    test('répartition par jour (lundi=0) et pic jour', () {
      // 2024-01-01 lundi, 2024-01-03 mercredi.
      final s = computeOutageStats([
        _report(reportedAt: DateTime(2024, 1, 1, 8)), // lundi
        _report(reportedAt: DateTime(2024, 1, 3, 8)), // mercredi
        _report(reportedAt: DateTime(2024, 1, 3, 9)), // mercredi
      ]);
      expect(s.byWeekday[0], 1); // lundi
      expect(s.byWeekday[2], 2); // mercredi
      expect(s.peakWeekday, 2);
    });

    test(
      'coupure sans reportedAt : compte dans total, pas dans les histos',
      () {
        final s = computeOutageStats([_report()]);
        expect(s.total, 1);
        expect(s.byHour.every((v) => v == 0), isTrue);
        expect(s.byWeekday.every((v) => v == 0), isTrue);
      },
    );
  });
}
