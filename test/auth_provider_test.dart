import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/providers/auth_provider.dart';
import 'package:lightcutoff_app/repositories/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository service;

  setUp(() {
    service = MockAuthRepository();
    when(
      () => service.authStateChanges,
    ).thenAnswer((_) => Stream<User?>.value(null));
  });

  AuthProvider build() => AuthProvider(repository: service);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('login - mapping des erreurs', () {
    test('mauvais identifiants', () async {
      when(
        () => service.signInWithIdentifier(
          identifier: any(named: 'identifier'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'wrong-password'));

      final provider = build();
      final ok = await provider.login(identifier: 'pseudo', password: 'x');

      expect(ok, isFalse);
      expect(provider.error, 'Email ou mot de passe incorrect.');
    });

    test('compte désactivé', () async {
      when(
        () => service.signInWithIdentifier(
          identifier: any(named: 'identifier'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AccountDisabledException());

      final provider = build();
      final ok = await provider.login(identifier: 'a@b.com', password: 'x');

      expect(ok, isFalse);
      expect(provider.error, 'Ce compte a été désactivé.');
    });

    test('email déjà utilisé (register)', () async {
      when(
        () => service.isUsernameAvailable(any()),
      ).thenAnswer((_) async => true);
      when(
        () => service.register(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          username: any(named: 'username'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phoneNumber: any(named: 'phoneNumber'),
          birthDate: any(named: 'birthDate'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      final provider = build();
      final ok = await provider.register(
        firstName: 'Will',
        lastName: 'Koua',
        username: 'willk',
        email: 'a@b.com',
        password: 'secret',
        phoneNumber: '+237600000000',
        birthDate: DateTime(2000, 1, 1),
      );

      expect(ok, isFalse);
      expect(provider.error, 'Cet email est déjà utilisé.');
    });

    test('pseudo déjà pris (register)', () async {
      when(
        () => service.register(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          username: any(named: 'username'),
          email: any(named: 'email'),
          password: any(named: 'password'),
          phoneNumber: any(named: 'phoneNumber'),
          birthDate: any(named: 'birthDate'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'username-already-in-use'));

      final provider = build();
      final ok = await provider.register(
        firstName: 'Will',
        lastName: 'Koua',
        username: 'willk',
        email: 'a@b.com',
        password: 'secret',
      );

      expect(ok, isFalse);
      expect(provider.error, 'Ce pseudo est déjà pris.');
    });
  });

  test('login réussi -> pas d\'erreur', () async {
    when(
      () => service.signInWithIdentifier(
        identifier: any(named: 'identifier'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async {});

    final provider = build();
    final ok = await provider.login(identifier: 'willk', password: 'secret');

    expect(ok, isTrue);
    expect(provider.error, isNull);
  });

  test('état initial -> unauthenticated après le flux', () async {
    final provider = build();
    await settle();
    expect(provider.status, AuthStatus.unauthenticated);
  });
}
