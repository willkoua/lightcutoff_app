import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:lightcutoff_app/models/enums.dart';
import 'package:lightcutoff_app/models/geo.dart';
import 'package:lightcutoff_app/models/report.dart';
import 'package:lightcutoff_app/utils/share_report.dart';

Report _report({
  ServiceType service = ServiceType.electricity,
  OutageStatus status = OutageStatus.ongoing,
  int confirmations = 12,
  GeoArea location = const GeoArea(
    country: 'Cameroun',
    countryCode: 'CM',
    region: 'Centre',
    city: 'Yaoundé',
    neighborhood: 'Bastos',
  ),
}) => Report(
  id: 'abc123',
  userId: 'u1',
  status: status,
  serviceType: service,
  position: const GeoPosition(lat: 3.89, lng: 11.52),
  location: location,
  confirmationCount: confirmations,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations fr;
  late AppLocalizations en;
  setUpAll(() async {
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('message FR : emoji, zone courte, pluriel, lien en dernière ligne', () {
    final msg = buildReportShareMessage(
      fr,
      _report(),
      'https://njuka.app/s/abc123',
    );
    expect(msg, contains("⚡ Coupure d'électricité à Bastos, Yaoundé"));
    expect(msg, contains('12 voisins confirment'));
    expect(msg, contains('Suivie en direct sur NJUKA'));
    expect(msg.split('\n').last, 'https://njuka.app/s/abc123');
    // Zone COURTE : ni région ni pays dans le message.
    expect(msg, isNot(contains('Centre')));
    expect(msg, isNot(contains('Cameroun')));
  });

  test('message EN : eau + singulier', () {
    final msg = buildReportShareMessage(
      en,
      _report(service: ServiceType.water, confirmations: 1),
      'url',
    );
    expect(msg, contains('💧 Water outage in Bastos, Yaoundé'));
    expect(msg, contains('1 neighbor confirms'));
  });

  test('zéro confirmation : « à l\'instant »', () {
    final msg = buildReportShareMessage(fr, _report(confirmations: 0), 'url');
    expect(msg, contains("signalée à l'instant"));
  });

  test('résolue : suffixe (rétablie)', () {
    final msg = buildReportShareMessage(
      fr,
      _report(status: OutageStatus.resolved),
      'url',
    );
    expect(msg, contains('(rétablie)'));
  });

  test('zone vide : pas de préposition orpheline', () {
    final msg = buildReportShareMessage(
      fr,
      _report(location: const GeoArea()),
      'url',
    );
    expect(msg, contains("⚡ Coupure d'électricité ·"));
    expect(msg, isNot(contains(' à  ')));
  });
}
