import '../models/confirmation.dart';
import '../models/report.dart';
import '../models/restoration.dart';

/// Contrat d'accès aux coupures et à leurs confirmations / rétablissements.
/// L'implémentation concrète (Firestore) est interchangeable.
abstract class ReportRepository {
  Stream<List<Report>> watchReports({int limit, String? countryCode});

  /// Flux d'**un** report par id (`null` s'il n'existe pas ou est archivé).
  /// Permet à l'écran détail d'afficher un report même **hors** de la fenêtre
  /// temps réel : ouverture depuis une notification push, depuis l'anti-doublon
  /// (« voir mon signalement »), ou un lien profond.
  Stream<Report?> watchReport(String reportId);

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
  /// position du confirmeur au moment du vote, conservée sur le doc de vote pour
  /// une éventuelle estimation d'étendue ultérieure ; `null` si indisponible.
  Future<void> confirmReport(
    String reportId,
    String uid, {
    String? geohash,
    double? lat,
    double? lng,
  });

  /// Déclare que le courant est revenu chez [uid] pour cette coupure.
  /// Un seul vote par utilisateur — sans effet si déjà déclaré. Incrémente
  /// `restorationCount` du report parent dans une transaction. [geohash] =
  /// cellule grossière (≈1,2 km) de la position du confirmeur au moment du
  /// vote, conservée sur le doc pour une éventuelle estimation d'étendue ;
  /// `null` si indisponible.
  Future<void> markRestored(String reportId, String uid, {String? geohash});

  /// Flux des déclarations de rétablissement d'une coupure.
  Stream<List<Restoration>> watchRestorations(String reportId);

  /// Indique si [uid] a déjà déclaré le rétablissement pour ce report.
  Future<bool> hasRestored(String reportId, String uid);

  /// Déclare « pas de coupure chez moi » (réponse **Non** au prompt de
  /// proximité). Signal négatif précieux : il **délimite l'emprise** de la
  /// coupure (frontière de la tache d'huile des notifications). Un doc par
  /// utilisateur (`denials/{uid}`) ; n'affecte AUCUN compteur du report.
  /// [lat]/[lng] = position exacte (lecture admin/owner only, cf. règles).
  Future<void> denyReport(
    String reportId,
    String uid, {
    String? geohash,
    double? lat,
    double? lng,
  });

  /// Indique si [uid] a déjà répondu « pas chez moi » pour ce report.
  Future<bool> hasDenied(String reportId, String uid);
}
