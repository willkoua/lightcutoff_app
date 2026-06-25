import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/providers/auth_provider.dart';
import 'package:lightcutoff_app/repositories/auth_repository.dart';
import 'package:lightcutoff_app/services/notification_service.dart';
import 'package:lightcutoff_app/widgets/anonymous_first_report_sheet.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockNotificationService extends Mock implements NotificationService {}

Widget _wrap({required AuthProvider auth, required Widget child}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(() => registerFallbackValue(const GeoArea()));

  late _MockAuthRepository service;
  late _MockNotificationService notifs;

  setUp(() {
    service = _MockAuthRepository();
    notifs = _MockNotificationService();
    when(
      () => service.authStateChanges,
    ).thenAnswer((_) => Stream<User?>.value(null));
    when(() => service.signInAnonymously()).thenAnswer((_) async {});
    when(() => notifs.unregister()).thenAnswer((_) async {});
  });

  AuthProvider buildAuth({required bool anonymous}) {
    when(() => service.isAnonymous).thenReturn(anonymous);
    return AuthProvider(repository: service, notifications: notifs);
  }

  testWidgets(
    'session non anonyme → no-op (flag NON posé, sheet pas affichée)',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final auth = buildAuth(anonymous: false);
      late BuildContext capturedCtx;
      await tester.pumpWidget(
        _wrap(
          auth: auth,
          child: Builder(
            builder: (ctx) {
              capturedCtx = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      await showAnonymousFirstReportHintIfNeeded(capturedCtx);
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAnonymousFirstReportHintSeenKey), isNull);
      expect(find.byType(AnonymousFirstReportHintSheet), findsNothing);
    },
  );

  testWidgets(
    'session anonyme 1ʳᵉ fois → marque le flag + affiche la bottom-sheet',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final auth = buildAuth(anonymous: true);
      late BuildContext capturedCtx;
      await tester.pumpWidget(
        _wrap(
          auth: auth,
          child: Builder(
            builder: (ctx) {
              capturedCtx = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();

      // Lance la modale ; on ne l'attend pas (elle ne se ferme pas seule).
      // ignore: unawaited_futures
      showAnonymousFirstReportHintIfNeeded(capturedCtx);
      // Pump pour matérialiser le flag (set async) + l'animation d'ouverture.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAnonymousFirstReportHintSeenKey), isTrue);
      expect(find.byType(AnonymousFirstReportHintSheet), findsOneWidget);
    },
  );

  testWidgets('session anonyme mais flag déjà posé → sheet non rejouée', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kAnonymousFirstReportHintSeenKey: true,
    });
    final auth = buildAuth(anonymous: true);
    late BuildContext capturedCtx;
    await tester.pumpWidget(
      _wrap(
        auth: auth,
        child: Builder(
          builder: (ctx) {
            capturedCtx = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await showAnonymousFirstReportHintIfNeeded(capturedCtx);
    await tester.pump();

    expect(find.byType(AnonymousFirstReportHintSheet), findsNothing);
  });
}
