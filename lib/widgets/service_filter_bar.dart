import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../providers/region_provider.dart';
import 'service_visuals.dart';

/// Sélecteur segmenté **Tout / ⚡ Électricité / 💧 Eau** affiché en tête de la
/// Liste et de la Carte. Lit/écrit `RegionProvider.serviceFilter` (persisté
/// via SharedPreferences → rejoué au prochain lancement).
///
/// Visuellement aligné sur `SegmentedButton` Material 3 (cohérent avec le
/// sélecteur du formulaire de signalement).
class ServiceFilterBar extends StatelessWidget {
  const ServiceFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final region = context.watch<RegionProvider>();
    final selected = region.serviceFilter;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ServiceType?>(
          // ⚠️ Labels **courts** dans le filtre (« Élec. » / « Eau » en FR,
          // « Power » / « Water » en EN) pour tenir sur une seule ligne dans
          // un tiers de la largeur écran (≈ 110 px par segment sur mobile).
          // Les libellés complets (« Électricité ») restent partout ailleurs
          // (chip ReportCard, formulaire, stats…) via `serviceTypeLabel`.
          segments: [
            ButtonSegment<ServiceType?>(
              value: null,
              label: Text(l.serviceFilterAll),
              icon: const Icon(Icons.apps),
            ),
            ButtonSegment<ServiceType?>(
              value: ServiceType.electricity,
              label: Text(l.serviceFilterElectricity),
              icon: Icon(serviceTypeIcon(ServiceType.electricity)),
            ),
            ButtonSegment<ServiceType?>(
              value: ServiceType.water,
              label: Text(l.serviceFilterWater),
              icon: Icon(serviceTypeIcon(ServiceType.water)),
            ),
          ],
          selected: {selected},
          onSelectionChanged: (set) {
            // `set` est toujours non vide (single-selection). Pas d'await ;
            // l'état UI est rafraîchi par le notifier du RegionProvider.
            context.read<RegionProvider>().setServiceFilter(set.first);
          },
          showSelectedIcon: false,
        ),
      ),
    );
  }
}
