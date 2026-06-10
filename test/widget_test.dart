import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:lightcutoff_app/screens/splash_screen.dart';

void main() {
  testWidgets('Splash screen affiche le logo NJUKA', (tester) async {
    // Le splash utilise AppLocalizations (nom + slogan) → fournir les delegates.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: const SplashScreen(),
      ),
    );
    // Le halo est animé en boucle : on pompe quelques frames sans
    // pumpAndSettle (qui bouclerait à l'infini sur l'animation / l'indicateur).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Le splash affiche le logo (ampoule) centré et le nom de l'app.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('NJUKA'), findsOneWidget);
  });
}
