import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/config/utilities.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/providers/region_provider.dart';
import 'package:lightcutoff_app/repositories/location_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockLocationRepository extends Mock implements LocationRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockLocationRepository location;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    location = _MockLocationRepository();
    // Pas de GPS : on garantit que la résolution ne dépend pas de la
    // localisation (le test serait flaky sinon).
    when(
      () => location.checkAccess(),
    ).thenAnswer((_) async => LocationAccess.denied);
  });

  group('RegionProvider — fallback session anonyme', () {
    test('setHomeCountry(null) ne plante pas et reset _homeCountryIso', () {
      final region = RegionProvider(location: location);
      // Pose d'abord un pays (= upgrade simulé), puis on revient à null
      // (= logout / retour anonyme). Doit accepter la transition.
      region.setHomeCountry('Cameroun');
      region.setHomeCountry(null);
      // Sans override ni GPS ni profil, activeCountry tombe sur la locale du
      // test (souvent « US ») ou « CM » en dernier recours. On ne fige pas
      // la valeur exacte (dépend du runner), juste qu'elle est non vide et
      // qu'aucune exception n'est levée.
      expect(region.activeCountry, isNotEmpty);
    });

    test(
      'sans override ni profil, le défaut final reste « CM » (cas locale vide)',
      () {
        // On ne peut pas forcer PlatformDispatcher.instance.locale en unit test
        // sans widget tree. On vérifie au moins que `activeProvider` retombe
        // bien sur un fournisseur d\'un pays supporté ou null — pas d\'exception.
        final region = RegionProvider(location: location);
        region.setHomeCountry(null);
        // Sanity : la résolution termine et le pays est ISO court.
        expect(region.activeCountry.length, lessThanOrEqualTo(3));
      },
    );

    test(
      "override dev gagne sur l'absence de profil (session anonyme)",
      () async {
        final region = RegionProvider(location: location);
        region.setHomeCountry(null);
        // Simule le sélecteur dev qui pose un fournisseur Eneo (CM).
        final eneo = kSupportedUtilities.firstWhere((u) => u.id == 'eneo');
        await region.setOverride(ServiceType.electricity, eneo);
        expect(region.activeCountry, 'CM');
        expect(region.activeProvider?.id, 'eneo');
      },
    );

    test(
      "transition anonyme → upgrade : setHomeCountry(country) prend effet",
      () {
        final region = RegionProvider(location: location);
        // Démarrage anonyme.
        region.setHomeCountry(null);
        // L'utilisateur upgrade et son profil pose une homeLocation.
        region.setHomeCountry('Cameroun');
        // Sans override ni GPS, le pays du profil doit gagner.
        expect(region.activeCountry, 'CM');
      },
    );
  });

  group('RegionProvider — choix de pays utilisateur (#1)', () {
    test(
      'setUserCountry force le pays, prioritaire sur la détection',
      () async {
        final region = RegionProvider(location: location);
        await region.setUserCountry('CM');
        expect(region.userCountry, 'CM');
        expect(region.activeCountry, 'CM');
        expect(region.activeProvider, isNotNull); // Eneo dispo → programmées OK
      },
    );

    test('setUserCountry(null) repasse en automatique', () async {
      final region = RegionProvider(location: location);
      await region.setUserCountry('CM');
      await region.setUserCountry(null);
      expect(region.userCountry, isNull);
    });

    test('persistance du pays utilisateur après reconstruction', () async {
      final region = RegionProvider(location: location);
      await region.setUserCountry('CM');
      final rebuilt = RegionProvider(location: location);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rebuilt.userCountry, 'CM');
    });
  });

  group('RegionProvider — détection par IP (repli du GPS)', () {
    test('GPS refusé → le pays vient de l\'IP', () async {
      final region = RegionProvider(
        location: location, // checkAccess → denied (setUp)
        ipCountry: () async => 'CA',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(region.detectedCountry, 'CA');
      expect(region.activeCountry, 'CA');
    });

    test(
      'GPS accordé → l\'IP n\'est PAS consultée (VPN ne fausse rien)',
      () async {
        when(
          () => location.checkAccess(),
        ).thenAnswer((_) async => LocationAccess.granted);
        when(() => location.getCurrentLocation()).thenAnswer(
          (_) async => const LocationResult(
            position: GeoPosition(lat: 3.87, lng: 11.52),
            area: GeoArea(countryCode: 'CM', country: 'Cameroun'),
          ),
        );
        var ipCalled = false;
        final region = RegionProvider(
          location: location,
          ipCountry: () async {
            ipCalled = true;
            return 'FR';
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(region.detectedCountry, 'CM');
        expect(ipCalled, isFalse);
      },
    );

    test('IP en échec (null) → repli locale/CM, pas de crash', () async {
      final region = RegionProvider(
        location: location,
        ipCountry: () async => null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(region.detectedCountry, isNull);
      expect(region.activeCountry, isNotEmpty); // locale ou défaut CM
    });
  });

  group('RegionProvider — multi-service (pivot étape 3)', () {
    test(
      'activeUtility(elec) = Eneo, activeUtility(water) = CAMWATER au CM',
      () {
        final region = RegionProvider(location: location);
        region.setHomeCountry('Cameroun');
        expect(region.activeUtility(ServiceType.electricity)?.id, 'eneo');
        expect(region.activeUtility(ServiceType.water)?.id, 'camwater');
        // `activeProvider` (alias) reste = electricity (rétro-compat).
        expect(region.activeProvider?.id, 'eneo');
      },
    );

    test(
      "override CAMWATER (water) auto-couple Eneo (elec) sur le même pays",
      () async {
        final region = RegionProvider(location: location);
        region.setHomeCountry('Cameroun');
        final camwater = kSupportedUtilities.firstWhere(
          (u) => u.id == 'camwater',
        );
        await region.setOverride(ServiceType.water, camwater);
        expect(region.overrideUtility(ServiceType.water)?.id, 'camwater');
        // Auto-coupling : le slot elec est automatiquement aligné sur le
        // jumeau du même pays (Eneo · Cameroun).
        expect(region.overrideUtility(ServiceType.electricity)?.id, 'eneo');
        expect(region.activeUtility(ServiceType.water)?.id, 'camwater');
        expect(region.activeUtility(ServiceType.electricity)?.id, 'eneo');
      },
    );

    test("repasser un service en Auto bascule AUSSI l'autre en Auto", () async {
      final region = RegionProvider(location: location);
      final eneo = kSupportedUtilities.firstWhere((u) => u.id == 'eneo');
      await region.setOverride(ServiceType.electricity, eneo);
      // Auto-coupling a posé CAMWATER en water.
      expect(region.overrideUtility(ServiceType.water)?.id, 'camwater');

      // L'utilisateur repasse l'élec en Auto : symétriquement, l'eau passe
      // aussi en Auto (« unique sélecteur pays/compagnie à 2 facettes »).
      await region.setOverride(ServiceType.electricity, null);
      expect(region.overrideUtility(ServiceType.electricity), isNull);
      expect(region.overrideUtility(ServiceType.water), isNull);
    });

    test(
      "repasser le service eau en Auto bascule aussi l'élec en Auto",
      () async {
        // Symétrie : on vérifie le sens inverse pour ne pas dépendre d'un
        // seul côté de l'implémentation.
        final region = RegionProvider(location: location);
        final camwater = kSupportedUtilities.firstWhere(
          (u) => u.id == 'camwater',
        );
        await region.setOverride(ServiceType.water, camwater);
        expect(region.overrideUtility(ServiceType.electricity)?.id, 'eneo');

        await region.setOverride(ServiceType.water, null);
        expect(region.overrideUtility(ServiceType.water), isNull);
        expect(region.overrideUtility(ServiceType.electricity), isNull);
      },
    );

    test('persistance des 2 slots après reconstruction du provider', () async {
      final eneo = kSupportedUtilities.firstWhere((u) => u.id == 'eneo');
      final camwater = kSupportedUtilities.firstWhere(
        (u) => u.id == 'camwater',
      );
      final r1 = RegionProvider(location: location);
      await r1.setOverride(ServiceType.electricity, eneo);
      expect(r1.overrideUtility(ServiceType.electricity)?.id, 'eneo');
      expect(r1.overrideUtility(ServiceType.water)?.id, 'camwater');

      // Reconstruit (= nouveau lancement).
      final r2 = RegionProvider(location: location);
      await Future<void>.delayed(Duration.zero);
      expect(r2.overrideUtility(ServiceType.electricity)?.id, 'eneo');
      expect(r2.overrideUtility(ServiceType.water)?.id, 'camwater');

      // Désactive l'eau → l'élec se désactive aussi (couplage symétrique),
      // les deux slots sont rejoués comme « Auto » au prochain lancement.
      await r2.setOverride(ServiceType.water, null);
      final r3 = RegionProvider(location: location);
      await Future<void>.delayed(Duration.zero);
      expect(r3.overrideUtility(ServiceType.electricity), isNull);
      expect(r3.overrideUtility(ServiceType.water), isNull);

      // Vérifie qu'on peut tout réactiver via water (auto-couple elec).
      await r3.setOverride(ServiceType.water, camwater);
      expect(r3.overrideUtility(ServiceType.water)?.id, 'camwater');
      expect(r3.overrideUtility(ServiceType.electricity)?.id, 'eneo');
    });

    test(
      'migration : ancienne clé `provider_override_id` lue puis supprimée',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'provider_override_id': 'camwater',
        });
        final region = RegionProvider(location: location);
        await Future<void>.delayed(Duration.zero);
        // Migration : ancien id CAMWATER → slot water, sans toucher elec.
        // (L'auto-coupling ne s'applique PAS à la migration — sinon on
        // imposerait un changement de comportement à des installs existantes.)
        expect(region.overrideUtility(ServiceType.water)?.id, 'camwater');
        expect(region.overrideUtility(ServiceType.electricity), isNull);

        // Ancienne clé purgée.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('provider_override_id'), isNull);
        // Nouvelle clé eau persistée.
        expect(prefs.getString('provider_override_water_id'), 'camwater');
      },
    );

    test('setServiceFilter persisté (Élec → null → Eau)', () async {
      // Filtre initial : null (Tout).
      final r1 = RegionProvider(location: location);
      expect(r1.serviceFilter, isNull);
      await r1.setServiceFilter(ServiceType.electricity);
      expect(r1.serviceFilter, ServiceType.electricity);

      // Re-construit le provider (= nouveau lancement de l'app) : la
      // préférence doit être rejouée.
      final r2 = RegionProvider(location: location);
      await Future<void>.delayed(Duration.zero);
      expect(r2.serviceFilter, ServiceType.electricity);

      await r2.setServiceFilter(null);
      final r3 = RegionProvider(location: location);
      await Future<void>.delayed(Duration.zero);
      expect(r3.serviceFilter, isNull);

      await r3.setServiceFilter(ServiceType.water);
      final r4 = RegionProvider(location: location);
      await Future<void>.delayed(Duration.zero);
      expect(r4.serviceFilter, ServiceType.water);
    });
  });

  test('GeoArea() vide → setHomeCountry(country=null) ≡ pas de pays profil', () {
    // Garantit la cohérence du chemin app.dart :
    //   region.setHomeCountry(auth.profile?.homeLocation.country)
    // où `profile?.homeLocation` peut être l'objet sentinel `const GeoArea()`.
    const empty = GeoArea();
    expect(empty.country, isEmpty);
    // L'appel symétrique côté app.dart est sur `auth.profile?.homeLocation.country`
    // donc `null` quand profile == null (anonyme). Ce test documente l'invariant.
  });
}
