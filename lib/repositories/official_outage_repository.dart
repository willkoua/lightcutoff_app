import '../models/official_outage.dart';

/// Contrat de lecture des coupures officielles planifiées.
abstract class OfficialOutageRepository {
  /// Coupures planifiées à venir (date ≥ aujourd'hui) pour un **pays** (code
  /// ISO, ex. `CM`), triées par date.
  Future<List<OfficialOutage>> fetchUpcoming({required String country});
}
