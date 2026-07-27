import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/utils/username_generator.dart';

void main() {
  group('usernameSlug', () {
    test('minuscule, sans accents ni caractères spéciaux', () {
      expect(usernameSlug('Éloïse'), 'eloise');
      expect(usernameSlug('François-Xavier'), 'francoisxavier');
      expect(usernameSlug('N’Golo'), 'ngolo');
    });

    test('nom complet → premier mot (prénom)', () {
      expect(usernameSlug('Willy Kouagnia'), 'willy');
    });

    test('email → partie locale', () {
      expect(usernameSlug('willkoua@yahoo.fr'), 'willkoua');
    });

    test('germe vide ou inutilisable → repli « citoyen »', () {
      expect(usernameSlug(''), 'citoyen');
      expect(usernameSlug(null), 'citoyen');
      expect(usernameSlug('!!!'), 'citoyen');
    });

    test('tronqué à 15 caractères', () {
      expect(usernameSlug('abcdefghijklmnopqrstuvwxyz').length, 15);
    });
  });

  group('generateUsername', () {
    test('format slug_NNN avec suffixe déterministe (RNG injecté)', () {
      final u = generateUsername('Willy Kouagnia', random: Random(42));
      expect(u, matches(RegExp(r'^willy_\d{2,3}$')));
    });

    test('deux appels avec RNG différents → suffixes différents', () {
      final a = generateUsername('sam', random: Random(1));
      final b = generateUsername('sam', random: Random(2));
      expect(a, isNot(b));
    });
  });
}
