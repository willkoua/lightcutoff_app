import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/widgets/report_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('fr'),
  home: Scaffold(body: child),
);

Report _r({
  String? authorUsername,
  ServiceType serviceType = ServiceType.electricity,
}) => Report(
  id: 'r1',
  userId: 'u1',
  status: OutageStatus.ongoing,
  serviceType: serviceType,
  position: const GeoPosition(lat: 0, lng: 0),
  location: const GeoArea(city: 'Douala', countryCode: 'CM'),
  authorUsername: authorUsername,
);

void main() {
  testWidgets(
    "authorUsername null → AUCUNE référence à l'auteur affichée (session anonyme)",
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ReportCard(
            report: _r(authorUsername: null),
            isAuthor: false,
            onConfirm: () {},
            onMarkRestored: () {},
          ),
        ),
      );
      await tester.pump();

      // Aucun « @… » ne doit apparaître pour un report anonyme.
      // (Décision pivot 2026-06-24 : banaliser, pas de libellé « Anonyme ».)
      expect(find.textContaining('@'), findsNothing);
    },
  );

  testWidgets('authorUsername renseigné → chip @username affiché', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ReportCard(
          report: _r(authorUsername: 'willk'),
          isAuthor: false,
          onConfirm: () {},
          onMarkRestored: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('@willk'), findsOneWidget);
  });

  testWidgets(
    'authorUsername chaîne vide → traité comme absent (pas de chip)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ReportCard(
            report: _r(authorUsername: ''),
            isAuthor: false,
            onConfirm: () {},
            onMarkRestored: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('@'), findsNothing);
    },
  );

  testWidgets('chip service = « Électricité » pour un report élec', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ReportCard(
          report: _r(serviceType: ServiceType.electricity),
          isAuthor: false,
          onConfirm: () {},
          onMarkRestored: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Électricité'), findsOneWidget);
    expect(find.text('Eau'), findsNothing);
  });

  testWidgets('chip service = « Eau » pour un report eau', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReportCard(
          report: _r(serviceType: ServiceType.water),
          isAuthor: false,
          onConfirm: () {},
          onMarkRestored: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Eau'), findsOneWidget);
    expect(find.text('Électricité'), findsNothing);
  });
}
