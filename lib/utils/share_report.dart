import 'package:flutter/widgets.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../services/analytics_service.dart';

/// Partage d'un signalement — le levier viral n°1 (backlog 2026-07-07).
///
/// Le MESSAGE porte déjà l'information (service, zone, confirmations) : même
/// sans clic, le groupe WhatsApp est informé. Le LIEN pointe vers la page
/// publique `{shareBaseUrl}/s/{id}` (CF `renderReportShare` — aperçu riche
/// Open Graph, boutons stores avec UTM).

/// URL publique du signalement.
String reportShareUrl(Report report) =>
    '${AppConfig.shareBaseUrl}/s/${report.id}';

/// Zone COURTE (quartier, ville) — jamais région/pays : le message doit
/// rester lisible dans un aperçu WhatsApp.
String shareZoneLabel(Report report) {
  final parts =
      [
        report.location.neighborhood,
        report.location.city,
      ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
  return parts.join(', ');
}

/// Message complet (pur, testé) : « ⚡ Coupure d'électricité à Bastos,
/// Yaoundé · 12 voisins confirment\nSuivie en direct sur NJUKA :\n{lien} »
String buildReportShareMessage(AppLocalizations l, Report report, String url) {
  final water = report.serviceType == ServiceType.water;
  final emoji = water ? '💧' : '⚡';
  var title = water ? l.shareTitleWater : l.shareTitleElectricity;
  if (report.status == OutageStatus.resolved) {
    title += l.shareResolvedSuffix;
  }
  final zone = shareZoneLabel(report);
  final head = zone.isEmpty ? title : '$title ${l.shareZone(zone)}';
  final confirmations = l.shareConfirmations(report.confirmationCount);
  return '$emoji $head · $confirmations\n${l.shareTagline}\n$url';
}

/// Ouvre la feuille de partage native avec le message du signalement.
Future<void> shareReport(BuildContext context, Report report) async {
  final l = AppLocalizations.of(context);
  final message = buildReportShareMessage(l, report, reportShareUrl(report));
  // L'événement part avant la feuille : on mesure l'INTENTION de partage
  // (l'OS ne dit pas si l'utilisateur est allé au bout).
  await AnalyticsService.instance.logReportShared(
    service: report.serviceType.name,
    status: report.status.name,
  );
  await SharePlus.instance.share(ShareParams(text: message));
}
