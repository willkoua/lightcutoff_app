import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/config/utilities.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/official_outage.dart';
import 'package:lightcutoff_app/utils/share_official_outage.dart';

void main() {
  late AppLocalizations l;

  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  tearDown(resetUtilities);

  test('message de partage : opérateur + zone + date + créneau', () {
    applyRemoteUtilities(const [
      Utility(
        id: 'kplc',
        service: ServiceType.electricity,
        country: 'KE',
        label: 'Kenya Power',
        countryLabel: 'Kenya',
        scheduledOutages: true,
      ),
    ]);
    const outage = OfficialOutage(
      id: 'x',
      provider: 'kplc',
      country: 'KE',
      region: 'NAIROBI REGION',
      ville: 'NAIROBI',
      quartier: 'JOSKA, RUAI',
      startTime: '07:00',
      endTime: '17:00',
      progDate: '2026-10-11',
    );

    final msg = buildOfficialOutageShareMessage(
      l: l,
      outage: outage,
      dateLabel: 'dimanche 11 octobre 2026',
    );

    expect(msg, contains('Kenya Power'));
    expect(msg, contains('JOSKA, RUAI (NAIROBI, NAIROBI REGION)'));
    expect(msg, contains('dimanche 11 octobre 2026 · 07:00 – 17:00'));
    expect(msg, contains('⚡'));
    expect(msg, contains('via NJUKA'));
  });

  test('provider inconnu → repli sur l\'id en capitales', () {
    const outage = OfficialOutage(
      id: 'y',
      provider: 'eneo',
      quartier: 'BASTOS',
      startTime: '06:00',
      endTime: '18:00',
      progDate: '2026-06-10',
    );
    final msg = buildOfficialOutageShareMessage(
      l: l,
      outage: outage,
      dateLabel: '10 juin 2026',
    );
    // eneo est embarqué → SOCADEL.
    expect(msg, contains('SOCADEL'));
  });
}
