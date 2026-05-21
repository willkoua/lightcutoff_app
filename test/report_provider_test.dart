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

Report _report({String userId = 'u1'}) => Report(
      id: 'r1',
      userId: userId,
      status: OutageStatus.ongoing,
      position: const GeoPosition(lat: 0, lng: 0),
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
}
