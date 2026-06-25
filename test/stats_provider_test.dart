import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/providers/stats_provider.dart';
import 'package:lightcutoff_app/repositories/location_repository.dart';
import 'package:lightcutoff_app/repositories/report_repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockReportRepository extends Mock implements ReportRepository {}

class _MockLocationRepository extends Mock implements LocationRepository {}

Report _report({
  required String id,
  ServiceType serviceType = ServiceType.electricity,
}) => Report(
  id: id,
  userId: 'u1',
  status: OutageStatus.ongoing,
  serviceType: serviceType,
  position: const GeoPosition(lat: 0, lng: 0),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockReportRepository reports;
  late _MockLocationRepository location;

  setUp(() {
    reports = _MockReportRepository();
    location = _MockLocationRepository();
    // Zone indisponible (pas de GPS) → on isole « mine » dans les tests.
    when(
      () => location.checkAccess(),
    ).thenAnswer((_) async => LocationAccess.denied);
  });

  group('StatsProvider — filtre service (pivot étape 3)', () {
    test('mine = tous services, mineFor(elec) = elec seul', () async {
      when(() => reports.reportsByAuthor('u1')).thenAnswer(
        (_) async => [
          _report(id: 'e1'),
          _report(id: 'e2'),
          _report(id: 'w1', serviceType: ServiceType.water),
        ],
      );

      final provider = StatsProvider(reports: reports, location: location);
      await provider.load('u1');

      expect(provider.mine?.total, 3); // tous services
      expect(provider.mineFor(null)?.total, 3);
      expect(provider.mineFor(ServiceType.electricity)?.total, 2);
      expect(provider.mineFor(ServiceType.water)?.total, 1);
    });

    test('mineFor sans recharger après changement de filtre', () async {
      when(() => reports.reportsByAuthor('u1')).thenAnswer(
        (_) async => [
          _report(id: 'e1'),
          _report(id: 'w1', serviceType: ServiceType.water),
        ],
      );

      final provider = StatsProvider(reports: reports, location: location);
      await provider.load('u1');

      // Plusieurs lectures successives → aucune nouvelle requête réseau.
      provider.mineFor(ServiceType.electricity);
      provider.mineFor(ServiceType.water);
      provider.mineFor(null);
      verify(() => reports.reportsByAuthor('u1')).called(1);
    });

    test('avant load → mineFor/zoneFor renvoient null (status loading)', () {
      final provider = StatsProvider(reports: reports, location: location);
      expect(provider.status, StatsStatus.loading);
      expect(provider.mineFor(null), isNull);
      expect(provider.zoneFor(null), isNull);
    });
  });
}
