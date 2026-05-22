import '../models/confirmation.dart';
import '../models/report.dart';

/// Contrat d'accès aux coupures et à leurs confirmations.
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
}
