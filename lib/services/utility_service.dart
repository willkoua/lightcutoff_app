import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/utilities.dart';
import '../models/enums.dart';

/// Résultat du fetch du catalogue distant : entrées à appliquer + ids
/// explicitement désactivés (`enabled: false`).
typedef RemoteUtilities = ({List<Utility> upserts, Set<String> disabledIds});

/// Lit la collection **`utilities`** (source de vérité des compagnies
/// d'électricité/eau depuis le 2026-08-13 — lecture publique, écriture
/// Admin SDK uniquement).
///
/// Un seul fetch au démarrage : la donnée change quelques fois par an, la
/// persistance Firestore sert de cache hors-ligne. Échec **silencieux**
/// (`null`) : le registre embarqué reste alors en vigueur — le remote est
/// une surcouche, jamais un point de défaillance.
Future<RemoteUtilities?> fetchRemoteUtilities() async {
  try {
    final snap = await FirebaseFirestore.instance.collection('utilities').get();
    final upserts = <Utility>[];
    final disabled = <String>{};
    for (final doc in snap.docs) {
      final m = doc.data();
      if (m['enabled'] == false) {
        disabled.add(doc.id);
        continue;
      }
      final service = m['service'];
      final country = m['country'];
      final label = m['label'];
      final countryLabel = m['countryLabel'];
      // Doc malformé → ignoré (jamais de crash pour une donnée de référence).
      if (service is! String ||
          country is! String ||
          label is! String ||
          countryLabel is! String) {
        continue;
      }
      upserts.add(
        Utility(
          id: doc.id,
          service: ServiceType.fromName(service),
          country: country.toUpperCase(),
          label: label,
          countryLabel: countryLabel,
          countryAliases: [
            for (final a in (m['countryAliases'] as List? ?? const []))
              if (a is String) a.toLowerCase(),
          ],
        ),
      );
    }
    return (upserts: upserts, disabledIds: disabled);
  } catch (_) {
    return null;
  }
}
