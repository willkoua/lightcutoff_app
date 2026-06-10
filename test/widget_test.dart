import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightcutoff_app/screens/splash_screen.dart';

void main() {
  testWidgets('Splash screen affiche le logo NJUKA', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    // Le halo est animé en boucle : on pompe quelques frames sans
    // pumpAndSettle (qui bouclerait à l'infini sur l'animation).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Le splash affiche le logo (ampoule) centré.
    expect(find.byType(Image), findsOneWidget);
  });
}
