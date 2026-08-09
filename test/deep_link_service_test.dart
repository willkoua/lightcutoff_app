import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.reportIdFromUri', () {
    test('lien de partage valide', () {
      expect(
        DeepLinkService.reportIdFromUri(
          Uri.parse('https://njuka.app/s/AbC123xyz'),
        ),
        'AbC123xyz',
      );
    });

    test('chemins refusés : racine, autre page, id invalide, sous-chemin', () {
      for (final u in [
        'https://njuka.app/',
        'https://njuka.app/privacy',
        'https://njuka.app/s/',
        'https://njuka.app/s/ab', // trop court
        'https://njuka.app/s/abc123/extra',
        'https://njuka.app/s/<script>',
      ]) {
        expect(
          DeepLinkService.reportIdFromUri(Uri.parse(u)),
          isNull,
          reason: u,
        );
      }
    });
  });
}
