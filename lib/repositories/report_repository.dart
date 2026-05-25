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

  Future<void> createReport(Report report);

  Future<void> resolveReport(String reportId);

  Stream<List<Confirmation>> watchConfirmations(String reportId);

  Future<bool> hasConfirmed(String reportId, String uid);

  Future<void> confirmReport(String reportId, String uid);

  /// Déclare que le courant est revenu chez [uid] pour cette coupure.
  /// Un seul vote par utilisateur — sans effet si déjà déclaré. Incrémente
  /// `restorationCount` du report parent dans une transaction.
  Future<void> markRestored(String reportId, String uid);

  /// Flux des déclarations de rétablissement d'une coupure.
  Stream<List<Restoration>> watchRestorations(String reportId);

  /// Indique si [uid] a déjà déclaré le rétablissement pour ce report.
  Future<bool> hasRestored(String reportId, String uid);
}
