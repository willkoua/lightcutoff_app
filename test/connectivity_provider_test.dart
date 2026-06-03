import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/providers/connectivity_provider.dart';
import 'package:mocktail/mocktail.dart';

class MockConnectivity extends Mock implements Connectivity {}

void main() {
  late MockConnectivity conn;
  late StreamController<List<ConnectivityResult>> controller;

  setUp(() {
    conn = MockConnectivity();
    controller = StreamController<List<ConnectivityResult>>.broadcast();
    when(() => conn.onConnectivityChanged).thenAnswer((_) => controller.stream);
  });

  tearDown(() => controller.close());

  ConnectivityProvider build() => ConnectivityProvider(connectivity: conn);

  // Laisse le `_init` async (check initial + abonnement) se terminer.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('en ligne au démarrage (wifi)', () async {
    when(
      () => conn.checkConnectivity(),
    ).thenAnswer((_) async => [ConnectivityResult.wifi]);
    final p = build();
    await settle();
    expect(p.isOffline, isFalse);
  });

  test('hors ligne au démarrage (none)', () async {
    when(
      () => conn.checkConnectivity(),
    ).thenAnswer((_) async => [ConnectivityResult.none]);
    final p = build();
    await settle();
    expect(p.isOffline, isTrue);
  });

  test('liste vide = hors ligne', () async {
    when(
      () => conn.checkConnectivity(),
    ).thenAnswer((_) async => <ConnectivityResult>[]);
    final p = build();
    await settle();
    expect(p.isOffline, isTrue);
  });

  test('bascule online↔offline et ne notifie que sur changement', () async {
    when(
      () => conn.checkConnectivity(),
    ).thenAnswer((_) async => [ConnectivityResult.wifi]);
    final p = build();
    await settle();

    var notifs = 0;
    p.addListener(() => notifs++);

    // wifi → none : passe hors ligne (1 notif)
    controller.add([ConnectivityResult.none]);
    await settle();
    expect(p.isOffline, isTrue);
    expect(notifs, 1);

    // none → none : aucun changement (pas de notif)
    controller.add([ConnectivityResult.none]);
    await settle();
    expect(notifs, 1);

    // none → mobile : revient en ligne (1 notif)
    controller.add([ConnectivityResult.mobile]);
    await settle();
    expect(p.isOffline, isFalse);
    expect(notifs, 2);
  });
}
