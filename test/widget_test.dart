import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lightcutoff_app/screens/splash_screen.dart';

void main() {
  testWidgets('Splash screen affiche le nom de l\'app', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('fr'),
        home: SplashScreen(),
      ),
    );
    // L'extension d'AppLocalizations charge en async ; on pompe quelques frames
    // pour la laisser s'installer sans utiliser pumpAndSettle (qui boucle à
    // cause du CircularProgressIndicator du splash).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('NJUKA'), findsOneWidget);
  });
}
