import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../models/enums.dart';

/// Variante localisée de `formatting.dart#relativeTime`. Garde la même logique
/// (ancienneté en min/h/j/sem/mois/an), mais lit les libellés dans ARB pour
/// supporter FR/EN.
String relativeTimeL10n(BuildContext context, DateTime? date) {
  if (date == null) return '';
  final l = AppLocalizations.of(context);
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return l.relativeNow;
  if (diff.inMinutes < 60) return l.relativeMinutes(diff.inMinutes);
  if (diff.inHours < 24) return l.relativeHours(diff.inHours);
  if (diff.inDays < 7) return l.relativeDays(diff.inDays);
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 4) return l.relativeWeeks(weeks);
  final months = (diff.inDays / 30).floor();
  if (months < 12) return l.relativeMonths(months);
  return l.relativeYears((diff.inDays / 365).floor());
}

/// Libellé localisé d'un [OutageStatus].
String outageStatusLabel(BuildContext context, OutageStatus status) {
  final l = AppLocalizations.of(context);
  return status == OutageStatus.ongoing ? l.statusOngoing : l.statusResolved;
}

/// Libellé localisé d'un [OutageType].
String outageTypeLabel(BuildContext context, OutageType type) {
  final l = AppLocalizations.of(context);
  return switch (type) {
    OutageType.unplanned => l.outageTypeUnplanned,
    OutageType.scheduled => l.outageTypeScheduled,
  };
}

/// Libellé localisé d'un [UserRole].
String userRoleLabel(BuildContext context, UserRole role) {
  final l = AppLocalizations.of(context);
  return switch (role) {
    UserRole.citizen => l.roleCitizen,
    UserRole.operator => l.roleOperator,
    UserRole.admin => l.roleAdmin,
  };
}
