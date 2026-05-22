import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/config/app_constants.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/providers/report_provider.dart';
import 'package:lightcutoff_app/repositories/location_repository.dart';
import 'package:lightcutoff_app/repositories/report_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockReportRepository extends Mock implements ReportRepository {}

class MockLocationRepository extends Mock implements LocationRepository {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

Report _report({
  String id = 'r1',
  String userId = 'u1',
  OutageStatus status = OutageStatus.ongoing,
  double lat = 0,
  double lng = 0,
  String city = '',
  int confirmations = 0,
}) => Report(
  id: id,
  userId: userId,
  status: status,
  position: GeoPosition(lat: lat, lng: lng),
  location: GeoArea(city: city),
  confirmationCount: confirmations,
);

void main() {
  late MockReportRepository service;
  late MockLocationRepository location;
  late MockFirebaseAuth auth;
  late MockUser user;

  setUpAll(() {
    registerFallbackValue(_report());
  });

  setUp(() {
    service = MockReportRepository();
    location = MockLocationRepository();
    auth = MockFirebaseAuth();
    user = MockUser();

    when(
      () => service.watchReports(limit: any(named: 'limit')),
    ).thenAnswer((_) => Stream<List<Report>>.value(const []));
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn('u1');
  });

  ReportProvider build() =>
      ReportProvider(repository: service, location: location, auth: auth);

  test('submitReport réussit et appelle createReport', () async {
    when(() => location.getCurrentLocation()).thenAnswer(
      (_) async => const LocationResult(
        position: GeoPosition(lat: 3.8, lng: 11.5),
        area: GeoArea(city: 'Yaoundé'),
      ),
    );
    when(() => service.createReport(any())).thenAnswer((_) async {});

    final provider = build();
    final error = await provider.submitReport(cause: OutageCause.unplanned);

    expect(error, isNull);
    final captured =
        verify(() => service.createReport(captureAny())).captured;
    final report = captured.single as Report;
    expect(report.geohash, isNotNull);
    expect(report.geohash!.length, AppConstants.geohashPrecision);
  });

  test(
    'submitReport renvoie le message en cas d\'erreur de localisation',
    () async {
      when(
        () => location.getCurrentLocation(),
      ).thenThrow(const LocationException('Position introuvable.'));

      final provider = build();
      final error = await provider.submitReport(cause: OutageCause.unplanned);

      expect(error, 'Position introuvable.');
      verifyNever(() => service.createReport(any()));
    },
  );

  test('confirm délègue au service', () async {
    when(() => service.confirmReport('r1', 'u1')).thenAnswer((_) async {});
    final provider = build();
    expect(await provider.confirm('r1'), isTrue);
    verify(() => service.confirmReport('r1', 'u1')).called(1);
  });

  test('resolve délègue au service', () async {
    when(() => service.resolveReport('r1')).thenAnswer((_) async {});
    final provider = build();
    expect(await provider.resolve('r1'), isTrue);
    verify(() => service.resolveReport('r1')).called(1);
  });

  test('isAuthor distingue l\'auteur', () {
    final provider = build();
    expect(provider.isAuthor(_report(userId: 'u1')), isTrue);
    expect(provider.isAuthor(_report(userId: 'autre')), isFalse);
  });

  test('confirm refuse sa propre coupure', () async {
    when(() => service.watchReports(limit: any(named: 'limit'))).thenAnswer(
      (_) => Stream<List<Report>>.value([_report(id: 'mine', userId: 'u1')]),
    );
    final provider = build();
    await Future<void>.delayed(Duration.zero);

    final ok = await provider.confirm('mine');

    expect(ok, isFalse);
    verifyNever(() => service.confirmReport(any(), any()));
  });

  group('pagination', () {
    test('hasMore vrai quand un lot plein est reçu', () async {
      final fullPage = List.generate(
        AppConstants.reportsPageSize,
        (i) => _report(id: 'r$i'),
      );
      when(
        () => service.watchReports(limit: any(named: 'limit')),
      ).thenAnswer((_) => Stream<List<Report>>.value(fullPage));
      final provider = build();
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasMore, isTrue);
    });

    test('lot incomplet -> hasMore faux', () async {
      when(() => service.watchReports(limit: any(named: 'limit'))).thenAnswer(
        (_) => Stream<List<Report>>.value([_report(id: 'a')]),
      );
      final provider = build();
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasMore, isFalse);
      provider.loadMore(); // sans effet (rien à charger)
      verify(
        () => service.watchReports(limit: any(named: 'limit')),
      ).called(1);
    });

    test('loadMore re-souscrit avec une fenêtre élargie', () async {
      final fullPage = List.generate(
        AppConstants.reportsPageSize,
        (i) => _report(id: 'r$i'),
      );
      when(
        () => service.watchReports(limit: any(named: 'limit')),
      ).thenAnswer((_) => Stream<List<Report>>.value(fullPage));
      final provider = build();
      await Future<void>.delayed(Duration.zero);

      provider.loadMore();
      await Future<void>.delayed(Duration.zero);

      verify(
        () => service.watchReports(limit: any(named: 'limit')),
      ).called(2); // initial + loadMore
    });
  });

  group('findNearbyOngoing', () {
    // Yaoundé : 3.848, 11.502
    Future<ReportProvider> buildWith(List<Report> reports) async {
      when(
        () => service.watchReports(limit: any(named: 'limit')),
      ).thenAnswer((_) => Stream<List<Report>>.value(reports));
      final provider = build();
      await Future<void>.delayed(Duration.zero); // laisse le stream émettre
      return provider;
    }

    test('détecte une coupure en cours proche (< 500 m)', () async {
      final provider = await buildWith([
        _report(id: 'near', lat: 3.8485, lng: 11.502), // ~55 m
      ]);
      final found = provider.findNearbyOngoing(
        const GeoPosition(lat: 3.848, lng: 11.502),
      );
      expect(found?.id, 'near');
    });

    test('ignore une coupure trop loin (> 500 m)', () async {
      final provider = await buildWith([
        _report(id: 'far', lat: 3.9, lng: 11.6), // ~13 km
      ]);
      final found = provider.findNearbyOngoing(
        const GeoPosition(lat: 3.848, lng: 11.502),
      );
      expect(found, isNull);
    });

    test('ignore les coupures rétablies', () async {
      final provider = await buildWith([
        _report(
          id: 'resolved',
          status: OutageStatus.resolved,
          lat: 3.848,
          lng: 11.502,
        ),
      ]);
      final found = provider.findNearbyOngoing(
        const GeoPosition(lat: 3.848, lng: 11.502),
      );
      expect(found, isNull);
    });
  });

  group('filteredReports', () {
    Future<ReportProvider> buildWith(List<Report> reports) async {
      when(
        () => service.watchReports(limit: any(named: 'limit')),
      ).thenAnswer((_) => Stream<List<Report>>.value(reports));
      final provider = build();
      await Future<void>.delayed(Duration.zero);
      return provider;
    }

    test('recherche par zone', () async {
      final provider = await buildWith([
        _report(id: 'a', city: 'Yaoundé'),
        _report(id: 'b', city: 'Douala'),
      ]);
      provider.setQuery('yaound');
      expect(provider.filteredReports.map((r) => r.id), ['a']);
    });

    test('filtre par statut', () async {
      final provider = await buildWith([
        _report(id: 'a'),
        _report(id: 'b', status: OutageStatus.resolved),
      ]);
      provider.toggleStatusFilter(OutageStatus.resolved);
      expect(provider.filteredReports.map((r) => r.id), ['b']);
    });

    test('mes signalements uniquement', () async {
      final provider = await buildWith([
        _report(id: 'a', userId: 'u1'),
        _report(id: 'b', userId: 'autre'),
      ]);
      provider.toggleOnlyMine();
      expect(provider.filteredReports.map((r) => r.id), ['a']);
    });

    test('tri par nombre de confirmations', () async {
      final provider = await buildWith([
        _report(id: 'a', confirmations: 1),
        _report(id: 'b', confirmations: 5),
        _report(id: 'c', confirmations: 3),
      ]);
      provider.setSort(ReportSort.confirmed);
      expect(provider.filteredReports.map((r) => r.id), ['b', 'c', 'a']);
    });
  });
}
