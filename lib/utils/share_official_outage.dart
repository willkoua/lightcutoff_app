import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:share_plus/share_plus.dart';

import '../config/utilities.dart';
import '../models/enums.dart';
import '../models/official_outage.dart';

/// Partage et ajout au calendrier d'une **coupure officielle planifiée**.
/// Contrairement aux signalements, pas de page publique dédiée → le message
/// porte toute l'info (opérateur, zone, date, créneau), sans lien.

/// Libellé opérateur depuis le provider (SOCADEL, Kenya Power…), repli sur l'id.
String outageOperatorLabel(OfficialOutage o) =>
    utilityLabelForProvider(o.provider) ?? o.provider.toUpperCase();

String _emoji(OfficialOutage o) =>
    o.serviceType == ServiceType.water ? '💧' : '⚡';

/// Zone « quartier (ville, région) », parties vides ignorées.
String _placeLabel(OfficialOutage o) {
  final area = [
    o.ville,
    o.region,
  ].where((s) => s.isNotEmpty).join(', ');
  return area.isEmpty ? o.quartier : '${o.quartier} ($area)';
}

/// Message de partage (**pur**, testé) : opérateur + zone + date + créneau.
/// `dateLabel` est fourni formaté (dépend de la locale) pour garder la fonction
/// pure et testable sans contexte.
String buildOfficialOutageShareMessage({
  required AppLocalizations l,
  required OfficialOutage outage,
  required String dateLabel,
}) {
  final window = [
    outage.startTime,
    outage.endTime,
  ].where((s) => s.isNotEmpty).join(' – ');
  final when = window.isEmpty ? dateLabel : '$dateLabel · $window';
  return '${_emoji(outage)} ${l.officialOutageShareTitle} · '
      '${outageOperatorLabel(outage)}\n'
      '${_placeLabel(outage)}\n'
      '$when\n'
      '${l.officialOutageShareTagline}';
}

/// Date d'affichage localisée (« dim. 11 oct. 2026 »), repli sur la chaîne brute.
String _formatDate(String locale, String progDate) {
  try {
    return DateFormat.yMMMMEEEEd(locale).format(DateTime.parse(progDate));
  } catch (_) {
    return progDate;
  }
}

/// Ouvre la feuille de partage native avec le message de la coupure planifiée.
Future<void> shareOfficialOutage(
  BuildContext context,
  OfficialOutage outage,
) async {
  final l = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  final message = buildOfficialOutageShareMessage(
    l: l,
    outage: outage,
    dateLabel: _formatDate(locale, outage.progDate),
  );
  await SharePlus.instance.share(ShareParams(text: message));
}

/// Début/fin de l'événement. Préfère les instants absolus (`startsAt/endsAt`) ;
/// repli sur `progDate + startTime/endTime` interprétés en heure locale.
DateTime? _eventStart(OfficialOutage o) {
  if (o.startsAt != null) return o.startsAt;
  if (o.progDate.isEmpty) return null;
  final t = o.startTime.isEmpty ? '00:00' : o.startTime;
  return DateTime.tryParse('${o.progDate}T$t:00');
}

DateTime _eventEnd(OfficialOutage o, DateTime start) {
  if (o.endsAt != null) return o.endsAt!;
  if (o.progDate.isNotEmpty && o.endTime.isNotEmpty) {
    final e = DateTime.tryParse('${o.progDate}T${o.endTime}:00');
    if (e != null && e.isAfter(start)) return e;
  }
  return start.add(const Duration(hours: 1));
}

/// Ajoute la coupure au calendrier natif (ouvre l'app Agenda pré-remplie).
/// Renvoie `false` si la date est inexploitable.
Future<bool> addOutageToCalendar(
  BuildContext context,
  OfficialOutage outage,
) async {
  final l = AppLocalizations.of(context);
  final start = _eventStart(outage);
  if (start == null) return false;
  final end = _eventEnd(outage, start);

  final location = [
    outage.quartier,
    outage.ville,
    outage.region,
  ].where((s) => s.isNotEmpty).join(', ');

  final event = Event(
    title:
        'NJUKA : ${_emoji(outage)} ${l.officialOutageShareTitle} · '
        '${outageOperatorLabel(outage)}',
    description: outage.reason,
    location: location,
    startDate: start,
    endDate: end,
    allDay: false,
  );
  return Add2Calendar.addEvent2Cal(event);
}
