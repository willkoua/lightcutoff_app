import '../models/enums.dart';
import '../models/report.dart';

/// Statistiques agrégées calculées à partir d'une liste de [Report].
///
/// **Fonction pure** ([computeOutageStats]) → entièrement testable, sans I/O ni
/// dépendance Firebase. Sert les deux vues « mes coupures » et « ma zone ».
/// Aucune donnée personnelle : uniquement des agrégats (compte, durées,
/// répartitions horaires).
class OutageStats {
  /// Nombre total de coupures prises en compte.
  final int total;

  /// Coupures rétablies (statut résolu avec horodatages exploitables) — base de
  /// calcul des durées.
  final int resolvedCount;

  /// Durée cumulée des coupures rétablies.
  final Duration totalResolvedDuration;

  /// Répartition par heure de signalement (index 0–23). Somme ≤ [total]
  /// (les coupures sans `reportedAt` sont ignorées ici).
  final List<int> byHour;

  /// Répartition par jour de semaine (index 0 = lundi … 6 = dimanche).
  final List<int> byWeekday;

  const OutageStats({
    required this.total,
    required this.resolvedCount,
    required this.totalResolvedDuration,
    required this.byHour,
    required this.byWeekday,
  });

  /// État vide explicite (aucune coupure) — l'UI affiche un message dédié.
  bool get isEmpty => total == 0;

  /// Coupures encore en cours (sans durée connue).
  int get ongoingCount => total - resolvedCount;

  /// Durée moyenne d'une coupure rétablie, ou `null` si aucune n'est rétablie
  /// (évite toute division par zéro et toute moyenne trompeuse).
  Duration? get averageResolvedDuration {
    if (resolvedCount == 0) return null;
    return Duration(
      milliseconds: totalResolvedDuration.inMilliseconds ~/ resolvedCount,
    );
  }

  /// Heure (0–23) où le plus de coupures sont signalées, ou `null` si aucune
  /// donnée horaire. En cas d'égalité, la première heure atteignant le max.
  int? get peakHour {
    var maxCount = 0;
    int? hour;
    for (var h = 0; h < byHour.length; h++) {
      if (byHour[h] > maxCount) {
        maxCount = byHour[h];
        hour = h;
      }
    }
    return hour;
  }

  /// Jour de semaine (0 = lundi … 6 = dimanche) le plus touché, ou `null`.
  int? get peakWeekday {
    var maxCount = 0;
    int? day;
    for (var d = 0; d < byWeekday.length; d++) {
      if (byWeekday[d] > maxCount) {
        maxCount = byWeekday[d];
        day = d;
      }
    }
    return day;
  }
}

/// Calcule les [OutageStats] d'une liste de coupures. **Pur** : aucun effet de
/// bord, sûr sur une liste vide.
///
/// - La durée n'est comptée que pour les coupures **rétablies** disposant de
///   `reportedAt` ET `resolvedAt` cohérents (durée positive) — sinon ignorée.
/// - Les répartitions horaires utilisent `reportedAt` (heure locale de
///   l'appareil au moment du calcul) ; les coupures sans `reportedAt` ne
///   contribuent qu'au [total].
OutageStats computeOutageStats(List<Report> reports) {
  final byHour = List<int>.filled(24, 0);
  final byWeekday = List<int>.filled(7, 0);
  var resolvedCount = 0;
  var totalResolved = Duration.zero;

  for (final r in reports) {
    final reportedAt = r.reportedAt;
    if (reportedAt != null) {
      final local = reportedAt.toLocal();
      byHour[local.hour]++;
      byWeekday[local.weekday - 1]++; // DateTime.weekday : 1=lun … 7=dim
    }

    final resolvedAt = r.resolvedAt;
    if (r.status == OutageStatus.resolved &&
        reportedAt != null &&
        resolvedAt != null) {
      final d = resolvedAt.difference(reportedAt);
      if (!d.isNegative) {
        resolvedCount++;
        totalResolved += d;
      }
    }
  }

  return OutageStats(
    total: reports.length,
    resolvedCount: resolvedCount,
    totalResolvedDuration: totalResolved,
    byHour: byHour,
    byWeekday: byWeekday,
  );
}
