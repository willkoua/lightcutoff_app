import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../models/official_outage.dart';
import '../theme/app_colors.dart';

/// Carte d'une coupure **officielle planifiée**. Style bleu « planifié », visuellement
/// distinct des `ReportCard` (ambre) des signalements communautaires.
class OfficialOutageCard extends StatelessWidget {
  const OfficialOutageCard({super.key, required this.outage});

  final OfficialOutage outage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    String dateLabel = outage.progDate;
    try {
      dateLabel = DateFormat.yMMMMEEEEd(
        locale,
      ).format(DateTime.parse(outage.progDate));
    } catch (_) {
      // progDate inattendu : on garde la chaîne brute.
    }
    final window = [
      outage.startTime,
      outage.endTime,
    ].where((s) => s.isNotEmpty).join(' – ');
    final place = [
      outage.ville,
      outage.region,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge « Travaux planifiés · Eneo ».
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.planned.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.engineering_outlined,
                    size: 14,
                    color: AppColors.planned,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l.officialOutagesPlannedBadge,
                    style: const TextStyle(
                      color: AppColors.planned,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Quartier.
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.gray,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    outage.quartier,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            if (place.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  place,
                  style: const TextStyle(color: AppColors.gray, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            // Date + créneau horaire.
            Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: AppColors.gray,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    window.isEmpty ? dateLabel : '$dateLabel · $window',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (outage.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                outage.reason,
                style: const TextStyle(color: AppColors.gray, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
