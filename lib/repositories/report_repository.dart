import '../models/confirmation.dart';
import '../models/report.dart';

/// Contrat d'accès aux coupures et à leurs confirmations.
/// L'implémentation concrète (Firestore) est interchangeable.
abstract class ReportRepository {
  Stream<List<Report>> watchReports({int limit});

  Future<void> createReport(Report report);

  Future<void> resolveReport(String reportId);

  Stream<List<Confirmation>> watchConfirmations(String reportId);

  Future<bool> hasConfirmed(String reportId, String uid);

  Future<void> confirmReport(String reportId, String uid);
}
