import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/utils/formatting.dart';
import 'package:lightcutoff_app/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('valide', () => expect(Validators.email('a@b.com'), isNull));
    test('vide', () => expect(Validators.email(''), isNotNull));
    test('invalide', () => expect(Validators.email('abc'), isNotNull));
  });

  group('Validators.password', () {
    test('valide', () => expect(Validators.password('secret'), isNull));
    test('trop court', () => expect(Validators.password('123'), isNotNull));
    test('vide', () => expect(Validators.password(''), isNotNull));
  });

  group('Validators.required', () {
    test('rempli', () => expect(Validators.required('x'), isNull));
    test('vide', () => expect(Validators.required('  '), isNotNull));
  });

  group('relativeTime', () {
    test('null -> chaîne vide', () => expect(relativeTime(null), ''));

    test('quelques secondes', () {
      final d = DateTime.now().subtract(const Duration(seconds: 10));
      expect(relativeTime(d), 'à l\'instant');
    });

    test('minutes', () {
      final d = DateTime.now().subtract(const Duration(minutes: 5));
      expect(relativeTime(d), 'il y a 5 min');
    });

    test('heures', () {
      final d = DateTime.now().subtract(const Duration(hours: 3));
      expect(relativeTime(d), 'il y a 3 h');
    });

    test('jours', () {
      final d = DateTime.now().subtract(const Duration(days: 2));
      expect(relativeTime(d), 'il y a 2 j');
    });
  });
}
