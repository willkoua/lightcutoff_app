import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightcutoff_app/screens/splash_screen.dart';

void main() {
  testWidgets('Splash screen affiche le nom de l\'app', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('NJUKA'), findsOneWidget);
  });
}
