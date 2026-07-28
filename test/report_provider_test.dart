import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/config/app_constants.dart';
import 'package:lightcutoff_app/models/app_error.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/providers/report_provider.dart';
import 'package:lightcutoff_app/repositories/location_repository.dart';
import 'package:lightcutoff_app/repositories/report_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockReportRepository extends Mock implements ReportRepository {}

class MockLocationRepository extends Mock implements LocationRepository {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

Report _report({
  String id = 'r1',
  String userId = 'u1',
  OutageStatus status = OutageStatus.ongoing,
  ServiceType serviceType = ServiceType.electricity,
  double lat = 0,
  double lng = 0,
  String city = '',
  String countryCode = '',
  int confirmations = 0,
}) => Report(
  id: id,
  userId: userId,
  status: status,
  serviceType: serviceType,
  position: GeoPosition(lat: lat, lng: lng),
  location: GeoArea(city: city, countryCode: countryCode),
  confirmationCount: confirmations,
);

void main() {
  late MockReportRepository service;
  late MockLocationRepository location;
  late MockFirebaseAuth auth;
  late MockUser user;

  setUpAll(() {
    // Le provider s'enregistre comme WidgetsBindingObserver (cycle de vie) :
    // le binding de test doit être initialisé.
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(_report());
  });

  setUp(() {
    service = MockReportRepository();
    location = MockLocationRepository();
    auth = MockFirebaseAuth();
    user = MockUser();

    when(
      () => service.watchReports(
        limit: any(named: 'limit'),
        countryCode: any(named: 'countryCode'),
      ),
    ).thenAnswer((_) => Stream<List<Report>>.value(const []));
    // Par défaut, localisation non autorisée -> la proximité ne s'auto-active
    // pas au démarrage (préserve l'état de filtres attendu par les tests).
    when(
      () => location.checkAccess(),
    ).thenAnswer((_) async => LocationAccess.denied);
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn('u1');
    when(() => user.isAnonymous).thenReturn(false);
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
    final error = await provider.submitReport();

    expect(error, isNull);
    final captured = verify(() => service.createReport(captureAny())).captured;
    final report = captured.single as Report;
    expect(report.geohash, isNotNull);
    expect(report.geohash!.length, AppConstants.geohashPrecision);
  });

  test(
    'submitReport renvoie le code d\'erreur en cas d\'erreur de localisation',
    () async {
      when(
        () => location.getCurrentLocation(),
      ).thenThrow(const LocationException(AppError.locationNotFound));

      final provider = build();
      final error = await provider.submitReport();

      expect(error, AppError.locationNotFound);
      verifyNever(() => service.createReport(any()));
    },
  );

  test(
    'prepareReportFromDescription géocode la description en draft',
    () async {
      when(() => location.locationFromDescription('Douala')).thenAnswer(
        (_) async => const LocationResult(
          position: GeoPosition(lat: 4.05, lng: 9.7),
          area: GeoArea(city: 'Douala', countryCode: 'CM'),
        ),
      );
      final provider = build();
      final outcome = await provider.prepareReportFromDescription('Douala');

      expect(outcome.error, isNull);
      expect(outcome.draft, isNotNull);
      expect(outcome.draft!.position.lat, 4.05);
      expect(outcome.draft!.area.city, 'Douala');
    },
  );

  test(
    'prepareReportFromDescription renvoie locationNotFound si lieu inconnu',
    () async {
      when(
        () => location.locationFromDescription(any()),
      ).thenThrow(const LocationException(AppError.locationNotFound));
      final provider = build();
      final outcome = await provider.prepareReportFromDescription('xyz');

      expect(outcome.error, AppError.locationNotFound);
      expect(outcome.draft, isNull);
    },
  );

  test(
    'createFromDraft avec countryOverrideIso rattache le report au pays choisi',
    () async {
      when(() => service.createReport(any())).thenAnswer((_) async {});
      final provider = build();
      await provider.createFromDraft(
        const ReportDraft(
          position: GeoPosition(lat: 45.5, lng: -73.6),
          area: GeoArea(countryCode: 'CA', country: 'Canada', city: 'Montréal'),
        ),
        countryOverrideIso: 'CM',
      );
      final captured =
          verify(() => service.createReport(captureAny())).captured;
      final report = captured.single as Report;
      expect(report.location.countryCode, 'CM');
      expect(report.location.city, 'Montréal'); // le reste de la zone est gardé
    },
  );

  test('createFromDraft sans override garde le pays géocodé', () async {
    when(() => service.createReport(any())).thenAnswer((_) async {});
    final provider = build();
    await provider.createFromDraft(
      const ReportDraft(
        position: GeoPosition(lat: 45.5, lng: -73.6),
        area: GeoArea(countryCode: 'CA', country: 'Canada'),
      ),
    );
    final captured = verify(() => service.createReport(captureAny())).captured;
    expect((captured.single as Report).location.countryCode, 'CA');
  });

  test('createFromDraft propage reportedAt (date de constatation)', () async {
    when(() => service.createReport(any())).thenAnswer((_) async {});
    final provider = build();
    final observed = DateTime(2026, 6, 20, 9, 30);
    await provider.createFromDraft(
      const ReportDraft(position: GeoPosition(lat: 1, lng: 2), area: GeoArea()),
      reportedAt: observed,
    );
    final captured = verify(() => service.createReport(captureAny())).captured;
    expect((captured.single as Report).reportedAt, observed);
  });

  test('createFromDraft sans reportedAt → null (horodatage serveur)', () async {
    when(() => service.createReport(any())).thenAnswer((_) async {});
    final provider = build();
    await provider.createFromDraft(
      const ReportDraft(position: GeoPosition(lat: 1, lng: 2), area: GeoArea()),
    );
    final captured = verify(() => service.createReport(captureAny())).captured;
    expect((captured.single as Report).reportedAt, isNull);
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

  test('markRestored délègue au service (auteur inclus)', () async {
    when(() => service.markRestored('r1', 'u1')).thenAnswer((_) async {});
    final provider = build();
    expect(await provider.markRestored('r1'), isTrue);
    verify(() => service.markRestored('r1', 'u1')).called(1);
  });

  test('archive : l\'auteur peut archiver son report', () async {
    when(
      () => service.watchReports(
        limit: any(named: 'limit'),
        countryCode: any(named: 'countryCode'),
      ),
    ).thenAnswer(
      (_) => Stream<List<Report>>.value([_report(id: 'mine', userId: 'u1')]),
    );
    when(() => service.archiveReport('mine')).thenAnswer((_) async {});
    final provider = build();
    await Future<void>.delayed(Duration.zero);

    expect(await provider.archive('mine'), isTrue);
    verify(() => service.archiveReport('mine')).called(1);
  });

  test('archive : refuse le report d\'un autre', () async {
    when(
      () => service.watchReports(
        limit: any(named: 'limit'),
        countryCode: any(named: 'countryCode'),
      ),
    ).thenAnswer(
      (_) => Stream<List<Report>>.value([_report(id: 'other', userId: 'x')]),
    );
    final provider = build();
    await Future<void>.delayed(Duration.zero);

    expect(await provider.archive('other'), isFalse);
    verifyNever(() => service.archiveReport(any()));
  });

  test('isAuthor distingue l\'auteur', () {
    final provider = build();
    expect(provider.isAuthor(_report(userId: 'u1')), isTrue);
    expect(provider.isAuthor(_report(userId: 'autre')), isFalse);
  });

  test('confirm refuse sa propre coupure', () async {
    when(
      () => service.watchReports(
        limit: any(named: 'limit'),
        countryCode: any(named: 'countryCode'),
      ),
    ).thenAnswer(
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
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer((_) => Stream<List<Report>>.value(fullPage));
      final provider = build();
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasMore, isTrue);
    });

    test('lot incomplet -> hasMore faux', () async {
      when(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer((_) => Stream<List<Report>>.value([_report(id: 'a')]));
      final provider = build();
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasMore, isFalse);
      provider.loadMore(); // sans effet (rien à charger)
      verify(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).called(1);
    });

    test('loadMore re-souscrit avec une fenêtre élargie', () async {
      final fullPage = List.generate(
        AppConstants.reportsPageSize,
        (i) => _report(id: 'r$i'),
      );
      when(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer((_) => Stream<List<Report>>.value(fullPage));
      final provider = build();
      await Future<void>.delayed(Duration.zero);

      provider.loadMore();
      await Future<void>.delayed(Duration.zero);

      verify(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).called(2); // initial + loadMore
    });
  });

  group('findNearbyOngoing', () {
    // Yaoundé : 3.848, 11.502
    Future<ReportProvider> buildWith(List<Report> reports) async {
      when(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
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

    test(
      'ignore les coupures d\'un autre service quand serviceType est fourni',
      () async {
        // Coupure d'électricité juste à côté du point où on veut signaler
        // une coupure d'eau → pas de doublon (incidents distincts).
        final provider = await buildWith([
          _report(
            id: 'elec-near',
            serviceType: ServiceType.electricity,
            lat: 3.848,
            lng: 11.502,
          ),
        ]);
        final foundWater = provider.findNearbyOngoing(
          const GeoPosition(lat: 3.848, lng: 11.502),
          serviceType: ServiceType.water,
        );
        expect(foundWater, isNull);

        // Sans filtre service → on retrouve bien la coupure (comportement
        // historique préservé).
        final foundAny = provider.findNearbyOngoing(
          const GeoPosition(lat: 3.848, lng: 11.502),
        );
        expect(foundAny?.id, 'elec-near');
      },
    );
  });

  group('filteredReports', () {
    Future<ReportProvider> buildWith(List<Report> reports) async {
      when(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
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

    test('cloisonnement par pays STRICT : seulement le pays actif', () async {
      final provider = await buildWith([
        _report(id: 'cm', countryCode: 'CM'),
        _report(id: 'ca', countryCode: 'CA'),
        _report(id: 'legacy'), // sans countryCode → exclu (strict)
      ]);
      provider.setCountryFilter('CM');
      // Seul CM passe : CA (autre pays) ET legacy (pays inconnu) sont exclus.
      expect(provider.filteredReports.map((r) => r.id).toSet(), {'cm'});
    });

    test('mode monde (admin) : affiche tous les pays', () async {
      final provider = await buildWith([
        _report(id: 'cm', countryCode: 'CM'),
        _report(id: 'ke', countryCode: 'KE'),
      ]);
      provider.setWorldwide(true);
      provider.setCountryFilter(null); // le proxy met le filtre à null en monde
      expect(provider.filteredReports.map((r) => r.id).toSet(), {'cm', 'ke'});
    });

    test('cloisonnement pays inactif si pays null → tout visible', () async {
      final provider = await buildWith([
        _report(id: 'cm', countryCode: 'CM'),
        _report(id: 'ca', countryCode: 'CA'),
      ]);
      provider.setCountryFilter(null);
      expect(provider.filteredReports.map((r) => r.id).toSet(), {'cm', 'ca'});
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

  group('filtre proximité (requête bornée par geohash)', () {
    test('setNearOnly utilise reportsWithinRadius comme base', () async {
      when(() => location.getCurrentLocation()).thenAnswer(
        (_) async => const LocationResult(
          position: GeoPosition(lat: 3.86, lng: 11.51),
          area: GeoArea(),
        ),
      );
      when(
        () => service.reportsWithinRadius(
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          radiusMeters: any(named: 'radiusMeters'),
        ),
      ).thenAnswer((_) async => [_report(id: 'near1'), _report(id: 'near2')]);

      final provider = build();
      await Future<void>.delayed(Duration.zero);

      final err = await provider.setNearOnly(true);

      expect(err, isNull);
      expect(provider.nearOnly, isTrue);
      expect(provider.filteredReports.map((r) => r.id), ['near1', 'near2']);
      verify(
        () => service.reportsWithinRadius(
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          radiusMeters: any(named: 'radiusMeters'),
        ),
      ).called(1);
    });

    test('« proximité » et « mes signalements » sont exclusifs', () async {
      when(() => location.getCurrentLocation()).thenAnswer(
        (_) async => const LocationResult(
          position: GeoPosition(lat: 3.86, lng: 11.51),
          area: GeoArea(),
        ),
      );
      when(
        () => service.reportsWithinRadius(
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          radiusMeters: any(named: 'radiusMeters'),
        ),
      ).thenAnswer((_) async => [_report(id: 'near')]);

      final provider = build();
      await Future<void>.delayed(Duration.zero);

      // Activer proximité désactive « mes signalements »…
      provider.toggleOnlyMine();
      expect(provider.onlyMine, isTrue);
      await provider.setNearOnly(true);
      expect(provider.nearOnly, isTrue);
      expect(provider.onlyMine, isFalse);

      // …et activer « mes signalements » désactive la proximité.
      provider.toggleOnlyMine();
      expect(provider.onlyMine, isTrue);
      expect(provider.nearOnly, isFalse);
    });

    test('erreur de localisation -> filtre désactivé + code', () async {
      when(
        () => location.getCurrentLocation(),
      ).thenThrow(const LocationException(AppError.locationNotFound));

      final provider = build();
      final err = await provider.setNearOnly(true);

      expect(err, AppError.locationNotFound);
      expect(provider.nearOnly, isFalse);
      verifyNever(
        () => service.reportsWithinRadius(
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          radiusMeters: any(named: 'radiusMeters'),
        ),
      );
    });
  });

  group('filtres par défaut', () {
    test('statut « en cours » + tri « activité », sans filtre actif', () {
      final provider = build();
      expect(provider.statusFilter, OutageStatus.ongoing);
      expect(provider.sort, ReportSort.active);
      expect(provider.hasActiveFilters, isFalse);
    });

    test('proximité activée au démarrage si localisation autorisée', () async {
      when(
        () => location.checkAccess(),
      ).thenAnswer((_) async => LocationAccess.granted);
      when(() => location.getCurrentLocation()).thenAnswer(
        (_) async => const LocationResult(
          position: GeoPosition(lat: 3.86, lng: 11.51),
          area: GeoArea(),
        ),
      );
      when(
        () => service.reportsWithinRadius(
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          radiusMeters: any(named: 'radiusMeters'),
        ),
      ).thenAnswer((_) async => [_report(id: 'near')]);

      final provider = build();
      await Future<void>.delayed(Duration.zero);

      expect(provider.nearOnly, isTrue);
      expect(provider.filteredReports.map((r) => r.id), ['near']);
    });

    test('proximité non activée si localisation refusée', () async {
      final provider = build();
      await Future<void>.delayed(Duration.zero);
      expect(provider.nearOnly, isFalse);
    });

    test(
      'proximité reste active même sans coupure proche (pas de repli)',
      () async {
        when(
          () => location.checkAccess(),
        ).thenAnswer((_) async => LocationAccess.granted);
        when(() => location.getCurrentLocation()).thenAnswer(
          (_) async => const LocationResult(
            position: GeoPosition(lat: 3.86, lng: 11.51),
            area: GeoArea(),
          ),
        );
        when(
          () => service.reportsWithinRadius(
            lat: any(named: 'lat'),
            lng: any(named: 'lng'),
            radiusMeters: any(named: 'radiusMeters'),
          ),
        ).thenAnswer((_) async => <Report>[]);

        final provider = build();
        await Future<void>.delayed(Duration.zero);

        // « À proximité » est le filtre par défaut et le RESTE même vide (état
        // vide explicite), au lieu de basculer sur la liste complète.
        expect(provider.nearOnly, isTrue);
        expect(provider.filteredReports, isEmpty);
      },
    );
  });

  group('filtre service (pivot étape 3)', () {
    const elecReport = Report(
      id: 'e1',
      userId: 'u1',
      status: OutageStatus.ongoing,
      // serviceType par défaut = electricity.
      position: GeoPosition(lat: 0, lng: 0),
    );
    const waterReport = Report(
      id: 'w1',
      userId: 'u1',
      status: OutageStatus.ongoing,
      serviceType: ServiceType.water,
      position: GeoPosition(lat: 0, lng: 0),
    );

    test('serviceFilter=null → reports élec ET eau visibles', () async {
      when(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer((_) => Stream.value([elecReport, waterReport]));

      final provider = build();
      await Future<void>.delayed(Duration.zero);
      provider.setServiceFilter(null);
      expect(provider.filteredReports.map((r) => r.id), ['e1', 'w1']);
    });

    test('serviceFilter=water filtre les reports élec', () async {
      when(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer((_) => Stream.value([elecReport, waterReport]));

      final provider = build();
      await Future<void>.delayed(Duration.zero);
      provider.setServiceFilter(ServiceType.water);
      expect(provider.filteredReports.map((r) => r.id), ['w1']);
    });

    test(
      'serviceFilter NE compte PAS dans hasActiveFilters (vue persistée)',
      () {
        final provider = build();
        expect(provider.hasActiveFilters, isFalse);
        provider.setServiceFilter(ServiceType.water);
        // Vue persistée (segmented control toujours visible) → exclu du
        // bandeau « filtres actifs » transitoires.
        expect(provider.hasActiveFilters, isFalse);
      },
    );
  });

  group('deny (« Non, pas chez moi »)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('délègue au service et écarte le prompt', () async {
      when(
        () => service.denyReport(
          'r1',
          'u1',
          geohash: any(named: 'geohash'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
        ),
      ).thenAnswer((_) async {});
      final provider = build();
      await Future<void>.delayed(Duration.zero);

      expect(await provider.deny('r1'), isTrue);
      verify(
        () => service.denyReport(
          'r1',
          'u1',
          geohash: any(named: 'geohash'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
        ),
      ).called(1);
    });

    test('refuse sa propre coupure', () async {
      when(
        () => service.watchReports(
          limit: any(named: 'limit'),
          countryCode: any(named: 'countryCode'),
        ),
      ).thenAnswer(
        (_) => Stream<List<Report>>.value([_report(id: 'mine', userId: 'u1')]),
      );
      final provider = build();
      await Future<void>.delayed(Duration.zero);

      expect(await provider.deny('mine'), isFalse);
      verifyNever(
        () => service.denyReport(
          any(),
          any(),
          geohash: any(named: 'geohash'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
        ),
      );
    });
  });

  group('promptCandidate (prompt d\'ouverture « Chez toi aussi ? »)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    // Active la proximité (fournit le centre) avec [reports] comme résultats.
    Future<ReportProvider> buildNear(List<Report> reports) async {
      when(
        () => location.checkAccess(),
      ).thenAnswer((_) async => LocationAccess.granted);
      when(() => location.getCurrentLocation()).thenAnswer(
        (_) async => const LocationResult(
          position: GeoPosition(lat: 3.86, lng: 11.51),
          area: GeoArea(),
        ),
      );
      when(
        () => service.reportsWithinRadius(
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
          radiusMeters: any(named: 'radiusMeters'),
        ),
      ).thenAnswer((_) async => reports);
      final provider = build();
      await Future<void>.delayed(Duration.zero);
      await provider.setNearOnly(true);
      await Future<void>.delayed(Duration.zero);
      return provider;
    }

    test('retourne la coupure en cours la plus proche (< 1 km)', () async {
      final provider = await buildNear([
        // ~110 m du centre.
        _report(id: 'near', userId: 'x', lat: 3.861, lng: 11.51),
        // ~2,2 km → hors rayon du prompt.
        _report(id: 'far', userId: 'x', lat: 3.88, lng: 11.51),
        // Proche mais c'est MA coupure → exclue.
        _report(id: 'mine', userId: 'u1', lat: 3.8605, lng: 11.51),
        // Proche mais résolue → exclue.
        _report(
          id: 'done',
          userId: 'x',
          status: OutageStatus.resolved,
          lat: 3.8602,
          lng: 11.51,
        ),
      ]);
      expect(provider.promptCandidate?.id, 'near');
    });

    test('exclut un report écarté (passer) ou déjà voté', () async {
      final provider = await buildNear([
        _report(id: 'near', userId: 'x', lat: 3.861, lng: 11.51),
      ]);
      expect(provider.promptCandidate?.id, 'near');

      provider.dismissPrompt('near');
      expect(provider.promptCandidate, isNull);
    });

    test('un deny écarte aussi le prompt', () async {
      when(
        () => service.denyReport(
          'near',
          'u1',
          geohash: any(named: 'geohash'),
          lat: any(named: 'lat'),
          lng: any(named: 'lng'),
        ),
      ).thenAnswer((_) async {});
      final provider = await buildNear([
        _report(id: 'near', userId: 'x', lat: 3.861, lng: 11.51),
      ]);
      expect(provider.promptCandidate?.id, 'near');

      await provider.deny('near');
      expect(provider.promptCandidate, isNull);
    });
  });
}
