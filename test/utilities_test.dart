import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/config/utilities.dart';
import 'package:lightcutoff_app/models/enums.dart';

const _cie = Utility(
  id: 'cie',
  service: ServiceType.electricity,
  country: 'CI',
  label: 'CIE',
  countryLabel: "Côte d'Ivoire",
  countryAliases: ["côte d'ivoire", 'ivory coast'],
);

void main() {
  tearDown(resetUtilities);

  group('mergeUtilities (embarqué ⊕ remote)', () {
    test('un id inconnu est ajouté (nouveau pays sans release)', () {
      final merged = mergeUtilities(kSupportedUtilities, const [_cie]);
      expect(merged.map((u) => u.id), contains('cie'));
      // L'embarqué reste en tête (ordre préservé).
      expect(merged.first.id, kSupportedUtilities.first.id);
    });

    test('un id existant est remplacé (renommage sans release)', () {
      const renamed = Utility(
        id: 'eneo',
        service: ServiceType.electricity,
        country: 'CM',
        label: 'NouveauNom',
        countryLabel: 'Cameroun',
      );
      final merged = mergeUtilities(kSupportedUtilities, const [renamed]);
      expect(merged.singleWhere((u) => u.id == 'eneo').label, 'NouveauNom');
      expect(merged.length, kSupportedUtilities.length);
    });

    test('un id désactivé est retiré, même embarqué', () {
      final merged = mergeUtilities(
        kSupportedUtilities,
        const [],
        disabledIds: {'camwater'},
      );
      expect(merged.map((u) => u.id), isNot(contains('camwater')));
    });
  });

  group('applyRemoteUtilities → résolutions', () {
    test('la Côte d\'Ivoire devient couverte après application du remote', () {
      expect(
        utilityForCountryAndService('CI', ServiceType.electricity),
        isNull,
      );
      applyRemoteUtilities(const [_cie]);
      expect(
        utilityForCountryAndService('CI', ServiceType.electricity)?.id,
        'cie',
      );
      expect(supportedCountries().map((c) => c.iso), contains('CI'));
      expect(countryLabelForIso('CI'), "Côte d'Ivoire");
      expect(isoFromCountryName('ivory coast'), 'CI');
    });

    test('resetUtilities revient à l\'embarqué', () {
      applyRemoteUtilities(const [_cie]);
      resetUtilities();
      expect(countryLabelForIso('CI'), isNull);
    });
  });
}
