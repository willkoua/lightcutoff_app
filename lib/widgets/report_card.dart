import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../models/enums.dart';
import '../models/report.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';

class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.report,
    required this.isAuthor,
    required this.onConfirm,
    required this.onMarkRestored,
    this.onTap,
  });

  final Report report;
  final bool isAuthor;
  final VoidCallback onConfirm;
  final VoidCallback onMarkRestored;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ongoing = report.status == OutageStatus.ongoing;
    final location =
        report.location.label.isEmpty
            ? l.reportDetailZoneUnknown
            : report.location.label;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusChip(
                    ongoing: ongoing,
                    label: outageStatusLabel(context, report.status),
                  ),
                  const Spacer(),
                  Text(
                    relativeTimeL10n(context, report.reportedAt),
                    style: const TextStyle(color: AppColors.gray, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                      location,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                outageTypeLabel(context, report.type),
                style: const TextStyle(color: AppColors.gray, fontSize: 13),
              ),
              if (report.authorUsername != null &&
                  report.authorUsername!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '@${report.authorUsername}',
                  style: const TextStyle(
                    color: AppColors.gray,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (report.description != null) ...[
                const SizedBox(height: 6),
                Text(report.description!),
              ],
              if (report.mediaUrl != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    report.mediaUrl!,
                    width: double.infinity,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // Ligne compteurs (toujours visible).
              Row(
                children: [
                  const Icon(
                    Icons.how_to_reg_outlined,
                    size: 18,
                    color: AppColors.gray,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l.reportCardConfirmationsCount(report.confirmationCount),
                    style: const TextStyle(color: AppColors.gray, fontSize: 13),
                  ),
                  if (report.restorationCount > 0) ...[
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.lightbulb,
                      size: 18,
                      color: AppColors.resolved,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${report.restorationCount}',
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
              // Boutons d'action : Wrap pour passer à la ligne sur petits écrans
              // (évite l'overflow horizontal quand les deux boutons sont là).
              if (ongoing) ...[
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    if (!isAuthor)
                      TextButton.icon(
                        onPressed: onConfirm,
                        icon: const Icon(Icons.thumb_up_outlined, size: 18),
                        label: Text(l.reportCardConfirm),
                      ),
                    TextButton.icon(
                      onPressed: onMarkRestored,
                      icon: const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(l.reportCardCourantRevenu),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.ongoing, required this.label});

  final bool ongoing;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ongoing ? AppColors.ongoing : AppColors.resolved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ongoing ? Icons.flash_off : Icons.flash_on,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
