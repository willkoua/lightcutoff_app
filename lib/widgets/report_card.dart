import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/report.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';

class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.report,
    required this.isAuthor,
    required this.onConfirm,
    required this.onResolve,
    this.onTap,
  });

  final Report report;
  final bool isAuthor;
  final VoidCallback onConfirm;
  final VoidCallback onResolve;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ongoing = report.status == OutageStatus.ongoing;
    final location =
        report.location.label.isEmpty ? 'Zone inconnue' : report.location.label;

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
                  _StatusChip(ongoing: ongoing, label: report.status.label),
                  const Spacer(),
                  Text(
                    relativeTime(report.reportedAt),
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
                report.cause.label,
                style: const TextStyle(color: AppColors.gray, fontSize: 13),
              ),
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
              Row(
                children: [
                  const Icon(
                    Icons.how_to_reg_outlined,
                    size: 18,
                    color: AppColors.gray,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${report.confirmationCount} confirmation'
                    '${report.confirmationCount > 1 ? 's' : ''}',
                    style: const TextStyle(color: AppColors.gray, fontSize: 13),
                  ),
                  const Spacer(),
                  if (ongoing && isAuthor)
                    TextButton(
                      onPressed: onResolve,
                      child: const Text('Marquer rétabli'),
                    )
                  else if (ongoing && !isAuthor)
                    TextButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.thumb_up_outlined, size: 18),
                      label: const Text('Confirmer'),
                    ),
                ],
              ),
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
