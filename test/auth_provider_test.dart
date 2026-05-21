import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/providers/auth_provider.dart';
import 'package:lightcutoff_app/services/auth_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService service;

  setUp(() {
    service = MockAuthService();
    when(() => service.authStateChanges)
        .thenAnswer((_) => Stream<User?>.value(null));
  });

  AuthProvider build() => AuthProvider(service: service);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('login - mapping des erreurs', () {
    test('mauvais identifiants', () async {
      when(() => service.signIn(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(FirebaseAuthException(code: 'wrong-password'));

      final provider = build();
      final ok = await provider.login(email: 'a@b.com', password: 'x');

      expect(ok, isFalse);
      expect(provider.error, 'Email ou mot de passe incorrect.');
    });

    test('compte désactivé', () async {
      when(() => service.signIn(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(const AccountDisabledException());

      final provider = build();
      final ok = await provider.login(email: 'a@b.com', password: 'x');

      expect(ok, isFalse);
      expect(provider.error, 'Ce compte a été désactivé.');
    });

    test('email déjà utilisé (register)', () async {
      when(() => service.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            displayName: any(named: 'displayName'),
            phoneNumber: any(named: 'phoneNumber'),
          )).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      final provider = build();
      final ok = await provider.register(
        email: 'a@b.com',
        password: 'secret',
        displayName: 'Test',
        phoneNumber: '+237600000000',
      );

      expect(ok, isFalse);
      expect(provider.error, 'Cet email est déjà utilisé.');
    });
  });

  test('login réussi -> pas d\'erreur', () async {
    when(() => service.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async {});

    final provider = build();
    final ok = await provider.login(email: 'a@b.com', password: 'secret');

    expect(ok, isTrue);
    expect(provider.error, isNull);
  });

  test('état initial -> unauthenticated après le flux', () async {
    final provider = build();
    await settle();
    expect(provider.status, AuthStatus.unauthenticated);
  });
}
