import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../models/app_error.dart';
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

/// Libellé localisé d'un [ServiceType] (« Électricité » / « Eau »).
String serviceTypeLabel(BuildContext context, ServiceType service) {
  final l = AppLocalizations.of(context);
  return switch (service) {
    ServiceType.electricity => l.serviceElectricity,
    ServiceType.water => l.serviceWater,
  };
}

/// Libellés d'action **dépendants du service** (électricité « courant » / eau
/// « eau »), pour que la confirmation et la déclaration de retour soient
/// cohérentes avec le type de coupure. L'accord en genre est porté par des
/// chaînes ARB distinctes (« revenu » vs « revenue »), pas par substitution.
bool _isWater(ServiceType s) => s == ServiceType.water;

/// Bouton « le courant/l'eau est revenu(e) chez moi » (écran détail).
String markRestoredButtonLabel(BuildContext context, ServiceType service) {
  final l = AppLocalizations.of(context);
  return _isWater(service)
      ? l.reportDetailMarkRestoredButtonWater
      : l.reportDetailMarkRestoredButton;
}

/// Compteur public « N personnes ont annoncé le retour du courant/de l'eau ».
String restorationCountLabel(
  BuildContext context,
  ServiceType service,
  int count,
) {
  final l = AppLocalizations.of(context);
  return _isWater(service)
      ? l.reportDetailRestorationCountWater(count)
      : l.reportDetailRestorationCount(count);
}

/// Puce courte « Courant revenu » / « Eau revenue » (carte report).
String serviceRestoredChipLabel(BuildContext context, ServiceType service) {
  final l = AppLocalizations.of(context);
  return _isWater(service)
      ? l.reportCardCourantRevenuWater
      : l.reportCardCourantRevenu;
}

/// Corps du dialogue de confirmation de coupure (« courant » / « eau »).
String confirmOutageBodyLabel(BuildContext context, ServiceType service) {
  final l = AppLocalizations.of(context);
  return _isWater(service) ? l.confirmOutageBodyWater : l.confirmOutageBody;
}

/// Titre du dialogue de retour (« Le courant est revenu ? » / « L'eau… »).
String confirmRestoreTitleLabel(BuildContext context, ServiceType service) {
  final l = AppLocalizations.of(context);
  return _isWater(service) ? l.confirmRestoreTitleWater : l.confirmRestoreTitle;
}

/// Corps du dialogue de retour.
String confirmRestoreBodyLabel(BuildContext context, ServiceType service) {
  final l = AppLocalizations.of(context);
  return _isWater(service) ? l.confirmRestoreBodyWater : l.confirmRestoreBody;
}

/// Motif de suppression « déjà revenu » dépendant du service.
String deleteReasonResolvedLabel(BuildContext context, ServiceType service) {
  final l = AppLocalizations.of(context);
  return _isWater(service)
      ? l.deleteReasonResolvedWater
      : l.deleteReasonResolved;
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

/// Message utilisateur localisé pour un [AppError] remonté par la couche
/// données (providers / services). Centralise la traduction des erreurs hors
/// `BuildContext`.
String appErrorLabel(BuildContext context, AppError error) {
  final l = AppLocalizations.of(context);
  return switch (error) {
    AppError.invalidEmail => l.errorInvalidEmail,
    AppError.wrongCredentials => l.errorWrongCredentials,
    AppError.emailInUse => l.errorEmailInUse,
    AppError.usernameInUse => l.errorUsernameInUse,
    AppError.weakPassword => l.errorWeakPassword,
    AppError.requiresRecentLogin => l.errorRequiresRecentLogin,
    AppError.networkRequestFailed => l.errorNetworkRequestFailed,
    AppError.accountDisabled => l.errorAccountDisabled,
    AppError.authFailed => l.errorAuthFailed,
    AppError.profileUpdateFailed => l.errorProfileUpdateFailed,
    AppError.socialSignInCancelled => l.errorSocialSignInCancelled,
    AppError.socialSignInFailed => l.errorSocialSignInFailed,
    AppError.accountExistsDifferentCredential =>
      l.errorAccountExistsDifferentCredential,
    AppError.notLoggedIn => l.errorNotLoggedIn,
    AppError.reportSubmitFailed => l.errorReportSubmitFailed,
    AppError.reportsLoadFailed => l.errorReportsLoadFailed,
    AppError.locationServicesDisabled => l.errorLocationServicesDisabled,
    AppError.locationPermissionDenied => l.errorLocationPermissionDenied,
    AppError.locationNotFound => l.errorLocationNotFound,
    AppError.locationUnavailable => l.errorLocationUnavailable,
    AppError.generic => l.errorGeneric,
  };
}
