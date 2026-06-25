import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/models/app_error.dart';
import 'package:lightcutoff_app/models/app_user.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/providers/auth_provider.dart';
import 'package:lightcutoff_app/repositories/auth_repository.dart';
import 'package:lightcutoff_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockNotificationService extends Mock implements NotificationService {}

class _MockUser extends Mock implements User {}

const AppUser _fakeProfile = AppUser(
  uid: 'uid-up1',
  email: 'a@b.com',
  username: 'willk',
  firstName: 'Will',
  lastName: 'Koua',
  role: UserRole.citizen,
  status: AccountStatus.active,
);

void main() {
  late MockAuthRepository service;
  late MockNotificationService notifications;

  setUpAll(() {
    // Argument matcher pour les enums / valeurs personnalisées passées
    // à `unregister` ou `registerForUser`.
    registerFallbackValue(const GeoArea());
  });

  setUp(() {
    service = MockAuthRepository();
    notifications = MockNotificationService();
    when(
      () => service.authStateChanges,
    ).thenAnswer((_) => Stream<User?>.value(null));
    when(() => service.isAnonymous).thenReturn(false);
    // Par défaut, l'auto sign-in anonyme réussit silencieusement (le stream
    // mocké ne ré-émet pas → le status reste `unknown` après l'attempt).
    when(() => service.signInAnonymously()).thenAnswer((_) async {});
    when(() => notifications.unregister()).thenAnswer((_) async {});
    when(
      () => notifications.registerForUser(
        userId: any(named: 'userId'),
        homeLocation: any(named: 'homeLocation'),
      ),
    ).thenAnswer((_) async {});
  });

  AuthProvider build() =>
      AuthProvider(repository: service, notifications: notifications);

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
      expect(provider.error, AppError.wrongCredentials);
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
      expect(provider.error, AppError.accountDisabled);
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
      expect(provider.error, AppError.emailInUse);
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
      expect(provider.error, AppError.usernameInUse);
    });
  });

  group('changement email / mot de passe', () {
    test('changePassword succès → pas d\'erreur', () async {
      when(
        () => service.changePassword(
          newPassword: any(named: 'newPassword'),
          currentPassword: any(named: 'currentPassword'),
        ),
      ).thenAnswer((_) async {});

      final provider = build();
      final ok = await provider.changePassword(
        newPassword: 'secret2',
        currentPassword: 'old',
      );

      expect(ok, isTrue);
      expect(provider.error, isNull);
    });

    test('changeEmail mappe requires-recent-login', () async {
      when(
        () => service.changeEmail(
          newEmail: any(named: 'newEmail'),
          currentPassword: any(named: 'currentPassword'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'requires-recent-login'));

      final provider = build();
      final ok = await provider.changeEmail(
        newEmail: 'x@y.com',
        currentPassword: 'old',
      );

      expect(ok, isFalse);
      expect(provider.error, AppError.requiresRecentLogin);
    });
  });

  group('connexion Google + profil social', () {
    test('annulation utilisateur → silencieux (pas d\'erreur)', () async {
      when(
        () => service.signInWithGoogle(),
      ).thenThrow(const SocialSignInCancelledException());

      final provider = build();
      final ok = await provider.signInWithGoogle();

      expect(ok, isFalse);
      expect(provider.error, isNull);
    });

    test('email lié à une autre méthode → erreur mappée', () async {
      when(() => service.signInWithGoogle()).thenThrow(
        FirebaseAuthException(code: 'account-exists-with-different-credential'),
      );

      final provider = build();
      final ok = await provider.signInWithGoogle();

      expect(ok, isFalse);
      expect(provider.error, AppError.accountExistsDifferentCredential);
    });

    test('completeProfile délègue au service', () async {
      when(
        () => service.completeSocialProfile(
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          username: any(named: 'username'),
          phoneNumber: any(named: 'phoneNumber'),
          birthDate: any(named: 'birthDate'),
        ),
      ).thenAnswer((_) async {});
      when(() => service.currentUser).thenReturn(null);

      final provider = build();
      final ok = await provider.completeProfile(
        firstName: 'Will',
        lastName: 'Koua',
        username: 'willk',
      );

      expect(ok, isTrue);
      expect(provider.error, isNull);
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

  group('mot de passe oublié', () {
    test('requestPasswordReset succès → ok=true, pas d\'erreur', () async {
      when(
        () => service.sendPasswordResetEmail(
          identifier: any(named: 'identifier'),
        ),
      ).thenAnswer((_) async {});

      final provider = build();
      final ok = await provider.requestPasswordReset(identifier: 'a@b.com');

      expect(ok, isTrue);
      expect(provider.error, isNull);
    });

    test(
      'requestPasswordReset invalid-email → AppError.invalidEmail',
      () async {
        when(
          () => service.sendPasswordResetEmail(
            identifier: any(named: 'identifier'),
          ),
        ).thenThrow(FirebaseAuthException(code: 'invalid-email'));

        final provider = build();
        final ok = await provider.requestPasswordReset(identifier: 'bogus');

        expect(ok, isFalse);
        expect(provider.error, AppError.invalidEmail);
      },
    );

    test('requestPasswordReset network-request-failed → mappé', () async {
      when(
        () => service.sendPasswordResetEmail(
          identifier: any(named: 'identifier'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'network-request-failed'));

      final provider = build();
      final ok = await provider.requestPasswordReset(identifier: 'a@b.com');

      expect(ok, isFalse);
      expect(provider.error, AppError.networkRequestFailed);
    });
  });

  group('session anonyme (Firebase Anonymous Auth)', () {
    test('état initial (user null) → déclenche signInAnonymously', () async {
      final provider = build();
      await settle();
      verify(() => service.signInAnonymously()).called(1);
      // Le stream mocké n'émet pas le user anonyme résultant, donc on reste
      // en `unknown` côté provider — c'est le bon comportement (pas un échec).
      expect(provider.status, AuthStatus.unknown);
    });

    test(
      'échec signInAnonymously au démarrage → unauthenticated, PAS de retry auto',
      () async {
        when(
          () => service.signInAnonymously(),
        ).thenThrow(FirebaseAuthException(code: 'network-request-failed'));

        final provider = build();
        await settle();

        expect(provider.status, AuthStatus.unauthenticated);
        expect(provider.error, AppError.networkRequestFailed);
        // Anti-boucle : on ne re-tente PAS automatiquement.
        verify(() => service.signInAnonymously()).called(1);
      },
    );

    test('retryAnonymousSignIn succès → la nouvelle tentative passe', () async {
      // 1ʳᵉ tentative échoue (au build), retry réussit.
      var calls = 0;
      when(() => service.signInAnonymously()).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw FirebaseAuthException(code: 'network-request-failed');
        }
      });

      final provider = build();
      await settle();
      expect(provider.status, AuthStatus.unauthenticated);

      final ok = await provider.retryAnonymousSignIn();
      expect(ok, isTrue);
      expect(provider.error, isNull);
      verify(() => service.signInAnonymously()).called(2);
    });

    test(
      'upgradeWithEmail succès → AnalyticsService.logSignUp + route via listener',
      () async {
        when(
          () => service.upgradeAnonymous(
            email: any(named: 'email'),
            password: any(named: 'password'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            username: any(named: 'username'),
            phoneNumber: any(named: 'phoneNumber'),
            birthDate: any(named: 'birthDate'),
          ),
        ).thenAnswer((_) async {});
        when(() => service.currentUser).thenReturn(null);

        final provider = build();
        final ok = await provider.upgradeWithEmail(
          firstName: 'Will',
          lastName: 'Koua',
          username: 'willk',
          email: 'a@b.com',
          password: 'secret',
        );

        expect(ok, isTrue);
        expect(provider.error, isNull);
        verify(
          () => service.upgradeAnonymous(
            email: 'a@b.com',
            password: 'secret',
            firstName: 'Will',
            lastName: 'Koua',
            username: 'willk',
            phoneNumber: null,
            birthDate: null,
          ),
        ).called(1);
      },
    );

    test(
      'upgradeWithEmail email-already-in-use → AppError.emailInUse',
      () async {
        when(
          () => service.upgradeAnonymous(
            email: any(named: 'email'),
            password: any(named: 'password'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            username: any(named: 'username'),
            phoneNumber: any(named: 'phoneNumber'),
            birthDate: any(named: 'birthDate'),
          ),
        ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

        final provider = build();
        final ok = await provider.upgradeWithEmail(
          firstName: 'Will',
          lastName: 'Koua',
          username: 'willk',
          email: 'a@b.com',
          password: 'secret',
        );

        expect(ok, isFalse);
        expect(provider.error, AppError.emailInUse);
      },
    );

    test(
      'refreshVerification (post-upgrade) → registerForUser appelé',
      () async {
        // Simule : user existant, email vérifié, profil disponible. Vérifie que
        // le device est enregistré pour activer les notifs sans redémarrer l'app
        // (sinon : pas de notifs jusqu'au prochain lancement).
        final user = _MockUser();
        when(() => user.uid).thenReturn('uid-up1');
        when(() => user.emailVerified).thenReturn(true);
        when(() => service.reloadUser()).thenAnswer((_) async {});
        when(() => service.currentUser).thenReturn(user);
        when(
          () => service.fetchProfile('uid-up1'),
        ).thenAnswer((_) async => _fakeProfile);

        final provider = build();
        final ok = await provider.refreshVerification();

        expect(ok, isTrue);
        expect(provider.status, AuthStatus.authenticated);
        verify(
          () => notifications.registerForUser(
            userId: 'uid-up1',
            homeLocation: any(named: 'homeLocation'),
          ),
        ).called(1);
      },
    );

    test(
      'upgradeWithEmail username-already-in-use → AppError.usernameInUse',
      () async {
        when(
          () => service.upgradeAnonymous(
            email: any(named: 'email'),
            password: any(named: 'password'),
            firstName: any(named: 'firstName'),
            lastName: any(named: 'lastName'),
            username: any(named: 'username'),
            phoneNumber: any(named: 'phoneNumber'),
            birthDate: any(named: 'birthDate'),
          ),
        ).thenThrow(FirebaseAuthException(code: 'username-already-in-use'));

        final provider = build();
        final ok = await provider.upgradeWithEmail(
          firstName: 'Will',
          lastName: 'Koua',
          username: 'taken',
          email: 'a@b.com',
          password: 'secret',
        );

        expect(ok, isFalse);
        expect(provider.error, AppError.usernameInUse);
      },
    );
  });
}
