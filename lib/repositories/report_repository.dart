import '../models/confirmation.dart';
import '../models/report.dart';
import '../models/restoration.dart';

/// Contrat d'accès aux coupures et à leurs confirmations / rétablissements.
/// L'implémentation concrète (Firestore) est interchangeable.
abstract class ReportRepository {
  Stream<List<Report>> watchReports({int limit});

  /// Coupures dans un rayon autour d'un point, via requête bornée par geohash
  /// (centre + voisines) affinée par distance exacte. Une seule lecture (pas
  /// de temps réel) ; ne renvoie que les coupures indexées (avec `geohash`).
  Future<List<Report>> reportsWithinRadius({
    required double lat,
    required double lng,
    required double radiusMeters,
  });

  /// Toutes les coupures créées par [uid] (pour les statistiques perso). Lecture
  /// unique, non paginée, archivées exclues. Tri par date décroissante.
  Future<List<Report>> reportsByAuthor(String uid);

  Future<void> createReport(Report report);

  Future<void> resolveReport(String reportId);

  /// Soft-delete : marque le report comme archivé (`archivedAt = now`). Il
  /// disparaît immédiatement des flux/listes/notifs. Sera purgé définitivement
  /// par le cron `purgeArchivedReports` après [AppConstants.archivedRetentionDays].
  Future<void> archiveReport(String reportId, {String? reason});

  Stream<List<Confirmation>> watchConfirmations(String reportId);

  Future<bool> hasConfirmed(String reportId, String uid);

  /// Confirme une coupure. [geohash] = cellule grossière (≈1,2 km) de la
  /// position du confirmeur, stockée sur le doc de vote pour le calcul serveur
  /// de l'emprise mesurée ; `null` si la position n'était pas disponible.
  Future<void> confirmReport(String reportId, String uid, {String? geohash});

  /// Déclare que le courant est revenu chez [uid] pour cette coupure.
  /// Un seul vote par utilisateur — sans effet si déjà déclaré. Incrémente
  /// `restorationCount` du report parent dans une transaction.
  Future<void> markRestored(String reportId, String uid);

  /// Flux des déclarations de rétablissement d'une coupure.
  Stream<List<Restoration>> watchRestorations(String reportId);

  /// Indique si [uid] a déjà déclaré le rétablissement pour ce report.
  Future<bool> hasRestored(String reportId, String uid);
}
