import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/official_outage.dart';
import '../repositories/official_outage_repository.dart';

/// Implémentation Firestore de [OfficialOutageRepository].
///
/// Requête **mono-champ** (`progDate >= aujourd'hui` + `orderBy progDate`) →
/// aucun index composite à déployer. Le filtrage région / recherche quartier
/// se fait côté client (volume modeste, ~quelques centaines de docs).
class OfficialOutageService implements OfficialOutageRepository {
  OfficialOutageService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('official_outages');

  @override
  Future<List<OfficialOutage>> fetchUpcoming() async {
    final snap =
        await _col
            .where('progDate', isGreaterThanOrEqualTo: _todayYmd())
            .orderBy('progDate')
            .get();
    return snap.docs.map(OfficialOutage.fromDoc).toList();
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
