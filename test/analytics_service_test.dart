import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/services/analytics_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockAnalytics extends Mock implements FirebaseAnalytics {}

void main() {
  // En test, aucun APP_ENV/USE_EMULATOR n'est défini → environnement = staging
  // (pas dev) → les events sont bien émis (pas court-circuités par la garde dev).
  late _MockAnalytics analytics;
  late AnalyticsService service;

  setUp(() {
    analytics = _MockAnalytics();
    service = AnalyticsService(analytics: analytics);
    when(
      () => analytics.logEvent(
        name: any(named: 'name'),
        parameters: any(named: 'parameters'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => analytics.logSignUp(signUpMethod: any(named: 'signUpMethod')),
    ).thenAnswer((_) async {});
  });

  test('logReportCreated émet l\'event report_created', () async {
    await service.logReportCreated();
    verify(
      () => analytics.logEvent(name: 'report_created', parameters: null),
    ).called(1);
  });

  test('logReportConfirmed émet report_confirmed', () async {
    await service.logReportConfirmed();
    verify(
      () => analytics.logEvent(name: 'report_confirmed', parameters: null),
    ).called(1);
  });

  test('logQuartierFollowed transmet le paramètre following', () async {
    await service.logQuartierFollowed(following: true);
    verify(
      () => analytics.logEvent(
        name: 'quartier_follow_toggled',
        parameters: {'following': true},
      ),
    ).called(1);
  });

  test('logSignUp passe par l\'event standard sign_up', () async {
    await service.logSignUp();
    verify(() => analytics.logSignUp(signUpMethod: 'email')).called(1);
  });
}
