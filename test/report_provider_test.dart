import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/providers/report_provider.dart';
import 'package:lightcutoff_app/services/location_service.dart';
import 'package:lightcutoff_app/services/report_service.dart';
import 'package:mocktail/mocktail.dart';

class MockReportService extends Mock implements ReportService {}

class MockLocationService extends Mock implements LocationService {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

Report _report({
  String id = 'r1',
  String userId = 'u1',
  OutageStatus status = OutageStatus.ongoing,
  double lat = 0,
  double lng = 0,
}) =>
    Report(
      id: id,
      userId: userId,
      status: status,
      position: GeoPosition(lat: lat, lng: lng),
    );

void main() {
  late MockReportService service;
  late MockLocationService location;
  late MockFirebaseAuth auth;
  late MockUser user;

  setUpAll(() {
    registerFallbackValue(_report());
  });

  setUp(() {
    service = MockReportService();
    location = MockLocationService();
    auth = MockFirebaseAuth();
    user = MockUser();

    when(() => service.watchReports())
        .thenAnswer((_) => Stream<List<Report>>.value(const []));
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn('u1');
  });

  ReportProvider build() =>
      ReportProvider(service: service, location: location, auth: auth);

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
    verify(() => service.createReport(any())).called(1);
  });

  test('submitReport renvoie le message en cas d\'erreur de localisation',
      () async {
    when(() => location.getCurrentLocation())
        .thenThrow(const LocationException('Position introuvable.'));

    final provider = build();
    final error = await provider.submitReport(cause: OutageCause.unplanned);

    expect(error, 'Position introuvable.');
    verifyNever(() => service.createReport(any()));
  });

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

  group('findNearbyOngoing', () {
    // Yaoundé : 3.848, 11.502
    Future<ReportProvider> buildWith(List<Report> reports) async {
      when(() => service.watchReports())
          .thenAnswer((_) => Stream<List<Report>>.value(reports));
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
        _report(id: 'resolved', status: OutageStatus.resolved, lat: 3.848, lng: 11.502),
      ]);
      final found = provider.findNearbyOngoing(
        const GeoPosition(lat: 3.848, lng: 11.502),
      );
      expect(found, isNull);
    });
  });
}
