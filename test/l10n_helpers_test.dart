import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:lightcutoff_app/models/app_error.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/utils/l10n_helpers.dart';

void main() {
  // Construit un BuildContext localisé en FR pour exercer les helpers (qui
  // lisent AppLocalizations.of(context)).
  Future<BuildContext> frContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('fr'),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return ctx;
  }

  testWidgets('labels statut / type / rôle (FR)', (tester) async {
    final ctx = await frContext(tester);
    expect(outageStatusLabel(ctx, OutageStatus.ongoing), 'En cours');
    expect(outageStatusLabel(ctx, OutageStatus.resolved), 'Rétabli');
    expect(outageTypeLabel(ctx, OutageType.unplanned), 'Coupure imprévue');
    expect(outageTypeLabel(ctx, OutageType.scheduled), 'Coupure programmée');
    expect(userRoleLabel(ctx, UserRole.citizen), 'Citoyen');
    expect(userRoleLabel(ctx, UserRole.operator), 'Opérateur');
    expect(userRoleLabel(ctx, UserRole.admin), 'Administrateur');
  });

  testWidgets('appErrorLabel mappe les codes (FR)', (tester) async {
    final ctx = await frContext(tester);
    expect(
      appErrorLabel(ctx, AppError.wrongCredentials),
      'Email ou mot de passe incorrect.',
    );
    expect(
      appErrorLabel(ctx, AppError.notLoggedIn),
      'Tu dois être connecté.',
    );
    expect(
      appErrorLabel(ctx, AppError.locationPermissionDenied),
      'Permission de localisation refusée.',
    );
    expect(
      appErrorLabel(ctx, AppError.generic),
      'Une erreur est survenue. Réessaie.',
    );
  });

  testWidgets('relativeTimeL10n choisit le bon palier', (tester) async {
    final ctx = await frContext(tester);
    final now = DateTime.now();
    expect(relativeTimeL10n(ctx, null), '');
    expect(relativeTimeL10n(ctx, now), "à l'instant");
    expect(
      relativeTimeL10n(ctx, now.subtract(const Duration(minutes: 5))),
      contains('min'),
    );
    expect(
      relativeTimeL10n(ctx, now.subtract(const Duration(hours: 5))),
      contains('h'),
    );
    expect(
      relativeTimeL10n(ctx, now.subtract(const Duration(days: 3))),
      contains('j'),
    );
    expect(
      relativeTimeL10n(ctx, now.subtract(const Duration(days: 14))),
      contains('sem'),
    );
    expect(
      relativeTimeL10n(ctx, now.subtract(const Duration(days: 70))),
      contains('mois'),
    );
    expect(
      relativeTimeL10n(ctx, now.subtract(const Duration(days: 400))),
      contains('an'),
    );
  });
}
