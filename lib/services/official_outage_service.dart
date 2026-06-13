import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/official_outage.dart';
import '../repositories/official_outage_repository.dart';

/// Implémentation Firestore de [OfficialOutageRepository].
///
/// Requête **mono-champ** (`where country ==`) → aucun index composite à
/// déployer. Le filtrage date (≥ aujourd'hui), le tri, la région et la
/// recherche quartier se font côté client (volume modeste par pays).
class OfficialOutageService implements OfficialOutageRepository {
  OfficialOutageService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('official_outages');

  @override
  Future<List<OfficialOutage>> fetchUpcoming({required String country}) async {
    final snap = await _col.where('country', isEqualTo: country).get();
    final today = _todayYmd();
    final items =
        snap.docs
            .map(OfficialOutage.fromDoc)
            .where((o) => o.progDate.compareTo(today) >= 0)
            .toList()
          ..sort((a, b) => a.progDate.compareTo(b.progDate));
    return items;
  }

  /// Date du jour au format YYYY-MM-DD (heure locale de l'appareil — les
  /// utilisateurs sont au Cameroun, fuseau de la donnée Eneo).
  static String _todayYmd() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }
}
