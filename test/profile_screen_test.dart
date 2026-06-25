import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:lightcutoff_app/models/app_user.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/providers/auth_provider.dart';
import 'package:lightcutoff_app/repositories/auth_repository.dart';
import 'package:lightcutoff_app/screens/profile_screen.dart';
import 'package:lightcutoff_app/services/notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockNotificationService extends Mock implements NotificationService {}

class _MockUser extends Mock implements User {}

const AppUser _profile = AppUser(
  uid: 'u1',
  email: 'a@b.com',
  username: 'willk',
  firstName: 'Will',
  lastName: 'Koua',
  role: UserRole.citizen,
  status: AccountStatus.active,
);

Widget _wrap(AuthProvider auth) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('fr'),
  home: ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: const ProfileScreen(),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(const GeoArea()));

  late _MockAuthRepository service;
  late _MockNotificationService notifs;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = _MockAuthRepository();
    notifs = _MockNotificationService();
    when(
      () => service.authStateChanges,
    ).thenAnswer((_) => const Stream<User?>.empty());
    when(() => service.signInAnonymously()).thenAnswer((_) async {});
    when(() => notifs.unregister()).thenAnswer((_) async {});
  });

  AuthProvider buildAuth({
    required bool anonymous,
    AppUser? profile,
    Stream<User?>? authStream,
  }) {
    when(() => service.isAnonymous).thenReturn(anonymous);
    when(
      () => service.authStateChanges,
    ).thenAnswer((_) => authStream ?? const Stream<User?>.empty());
    final p = AuthProvider(repository: service, notifications: notifs);
    // Injecte un profil pour le cas authentifié (sans avoir à dérouler tout
    // le flow auth listener dans un test widget).
    if (!anonymous && profile != null) {
      // Hack acceptable en test : le profil et le statut sont posés via le
      // listener `_onAuthStateChanged`. On simule un user authentifié.
      final user = _MockUser();
      when(() => user.uid).thenReturn(profile.uid);
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.emailVerified).thenReturn(true);
      when(() => user.email).thenReturn(profile.email);
      when(() => user.displayName).thenReturn(profile.fullName);
      when(
        () => service.fetchProfile(profile.uid),
      ).thenAnswer((_) async => profile);
      when(() => service.currentUser).thenReturn(user);
      // Ré-injecte un stream qui émet `user` → déclenche
      // `_onAuthStateChanged` → fetchProfile → status authenticated.
      when(
        () => service.authStateChanges,
      ).thenAnswer((_) => Stream<User?>.value(user));
    }
    return p;
  }

  testWidgets(
    "session anonyme → affiche le mur d'upgrade (heading + CTAs), pas le profil",
    (tester) async {
      final auth = buildAuth(anonymous: true);
      await tester.pumpWidget(_wrap(auth));
      await tester.pump();

      // Heading + CTA primaire + CTA secondaire visibles.
      expect(find.text('Tire le meilleur de NJUKA'), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(find.text('J\'ai déjà un compte'), findsOneWidget);
      // Aucune trace du nom de l'utilisateur ou du pseudo (profil masqué).
      expect(find.text('@willk'), findsNothing);
      expect(find.text('Will Koua'), findsNothing);
      // Pas d'icône Edit dans l'AppBar (cachée en anonyme).
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      // Mais l'icône Paramètres DOIT être présente (décision pivot : accès
      // toujours possible aux réglages, même en anonyme).
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'session authentifiée + profil → affiche le profil classique, pas le mur',
    (tester) async {
      // On crée un AuthProvider authenticated en construisant l'instance et
      // en lui propageant un user via le stream (le listener écrit alors le
      // profil dans _profile et passe le status à authenticated).
      final user = _MockUser();
      when(() => user.uid).thenReturn(_profile.uid);
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.emailVerified).thenReturn(true);
      when(() => user.email).thenReturn(_profile.email);
      when(() => user.displayName).thenReturn(_profile.fullName);
      when(() => service.isAnonymous).thenReturn(false);
      when(
        () => service.fetchProfile(_profile.uid),
      ).thenAnswer((_) async => _profile);
      when(() => service.currentUser).thenReturn(user);
      when(
        () => service.authStateChanges,
      ).thenAnswer((_) => Stream<User?>.value(user));
      when(
        () => notifs.registerForUser(
          userId: any(named: 'userId'),
          homeLocation: any(named: 'homeLocation'),
        ),
      ).thenAnswer((_) async {});

      final auth = AuthProvider(repository: service, notifications: notifs);
      await tester.pumpWidget(_wrap(auth));
      // Laisse le listener s'exécuter (microtask + fetchProfile).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Profil affiché.
      expect(find.text('Will Koua'), findsOneWidget);
      expect(find.text('@willk'), findsOneWidget);
      // Heading du mur d'upgrade absent.
      expect(find.text('Tire le meilleur de NJUKA'), findsNothing);
      // Icône Edit visible quand profile != null.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    },
  );
}
