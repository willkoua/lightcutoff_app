import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/utils/stadia_geocoding.dart';

/// Fixture réduite d'une VRAIE réponse de l'autocomplete Stadia
/// (capturée en live le 2026-08-13, requête « Bastos Yaound »).
const _fixture = {
  'features': [
    {
      'geometry': {
        'coordinates': [11.511124, 3.898433],
      },
      'properties': {
        'label': 'CTR Bastos, Yaoundé, Centre Region, Cameroon',
        'name': 'CTR Bastos',
        'layer': 'venue',
        'country': 'Cameroon',
        'country_code': 'CM',
        'region': 'Centre Region',
        'locality': 'Yaoundé',
      },
    },
    {
      'geometry': {
        'coordinates': [9.7, 4.05],
      },
      'properties': {
        'label': 'Douala, Littoral, Cameroon',
        'name': 'Douala',
        'layer': 'locality',
        'country': 'Cameroon',
        'country_code': 'CM',
        'region': 'Littoral',
      },
    },
    // Doc malformé → ignoré sans crash.
    {
      'geometry': {'coordinates': 'oops'},
      'properties': {'label': 'x'},
    },
  ],
};

void main() {
  test('parse une réponse réelle : venue et locality', () {
    final results = parseStadiaAutocomplete(
      Map<String, dynamic>.from(_fixture),
    );
    expect(results, hasLength(2)); // le malformé est ignoré

    final venue = results[0];
    expect(venue.position.lat, closeTo(3.898433, 1e-6));
    expect(venue.position.lng, closeTo(11.511124, 1e-6));
    expect(venue.area.countryCode, 'CM');
    expect(venue.area.city, 'Yaoundé');
    expect(venue.area.neighborhood, 'CTR Bastos');

    final city = results[1];
    expect(city.area.city, 'Douala'); // locality : le nom EST la ville
    expect(city.area.neighborhood, isEmpty);
  });

  test('réponses vides ou invalides → liste vide, jamais de crash', () {
    expect(parseStadiaAutocomplete(const {}), isEmpty);
    expect(parseStadiaAutocomplete(const {'features': 'nope'}), isEmpty);
  });
}
