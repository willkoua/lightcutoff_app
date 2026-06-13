import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/config/app_config.dart';

void main() {
  group('AppConfig.parseEnvironment', () {
    test('reconnaît les trois environnements (et leurs alias)', () {
      expect(AppConfig.parseEnvironment('dev'), AppEnvironment.dev);
      expect(AppConfig.parseEnvironment('development'), AppEnvironment.dev);
      expect(AppConfig.parseEnvironment('staging'), AppEnvironment.staging);
      expect(AppConfig.parseEnvironment('prod'), AppEnvironment.prod);
      expect(AppConfig.parseEnvironment('production'), AppEnvironment.prod);
    });

    test('insensible à la casse et aux espaces', () {
      expect(AppConfig.parseEnvironment(' STAGING '), AppEnvironment.staging);
      expect(AppConfig.parseEnvironment('Prod'), AppEnvironment.prod);
    });

    test('défaut sans APP_ENV : staging (comportement historique)', () {
      expect(AppConfig.parseEnvironment(''), AppEnvironment.staging);
      expect(AppConfig.parseEnvironment('inconnu'), AppEnvironment.staging);
    });

    test('rétro-compat : USE_EMULATOR=true sans APP_ENV → dev', () {
      expect(
        AppConfig.parseEnvironment('', legacyUseEmulator: true),
        AppEnvironment.dev,
      );
      // APP_ENV explicite prime sur le flag legacy.
      expect(
        AppConfig.parseEnvironment('staging', legacyUseEmulator: true),
        AppEnvironment.staging,
      );
    });
  });
}
