import 'package:flutter/widgets.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/utils/formatting.dart';
import 'package:lightcutoff_app/utils/validators.dart';

void main() {
  late AppLocalizations l;

  setUpAll(() async {
    // Charge le bundle FR pour valider les messages traduits.
    l = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  group('Validators.validateEmail', () {
    test('valide', () => expect(l.validateEmail('a@b.com'), isNull));
    test('vide', () => expect(l.validateEmail(''), isNotNull));
    test('invalide', () => expect(l.validateEmail('abc'), isNotNull));
  });

  group('Validators.validatePassword', () {
    test('valide', () => expect(l.validatePassword('secret'), isNull));
    test('trop court', () => expect(l.validatePassword('123'), isNotNull));
    test('vide', () => expect(l.validatePassword(''), isNotNull));
  });

  group('Validators.validateRequired', () {
    test('rempli', () => expect(l.validateRequired('x'), isNull));
    test('vide', () => expect(l.validateRequired('  '), isNotNull));
  });

  group('Validators.validateUsername', () {
    test('valide', () => expect(l.validateUsername('willk'), isNull));
    test(
      'normalise la casse',
      () => expect(l.validateUsername('WILLK'), isNull),
    );
    test('vide', () => expect(l.validateUsername(''), isNotNull));
    test('trop court', () => expect(l.validateUsername('ab'), isNotNull));
    test('trop long', () => expect(l.validateUsername('a' * 21), isNotNull));
    test(
      'caractères invalides',
      () => expect(l.validateUsername('will koua!'), isNotNull),
    );
  });

  group('Validators.validateIdentifier', () {
    test('rempli', () => expect(l.validateIdentifier('willk'), isNull));
    test('vide', () => expect(l.validateIdentifier('  '), isNotNull));
  });

  group('Validators.validatePhone', () {
    test('valide', () => expect(l.validatePhone('+237600000000'), isNull));
    test('vide', () => expect(l.validatePhone(''), isNotNull));
    test('trop court', () => expect(l.validatePhone('12345'), isNotNull));
  });

  group('formatDate', () {
    test('format JJ/MM/AAAA', () {
      expect(formatDate(DateTime(2024, 3, 7)), '07/03/2024');
    });
  });
}
