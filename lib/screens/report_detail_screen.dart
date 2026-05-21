import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/confirmation.dart';
import '../models/enums.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportProvider>();
    final report = provider.reportById(reportId);

    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Coupure')),
        body: const Center(child: Text('Coupure introuvable.')),
      );
    }

    final ongoing = report.status == OutageStatus.ongoing;
    final isAuthor = provider.isAuthor(report);

    return Scaffold(
      appBar: AppBar(title: const Text('Détail de la coupure')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatusChip(ongoing: ongoing, label: report.status.label),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.place_outlined,
            text: report.location.label.isEmpty
                ? 'Zone inconnue'
                : report.location.label,
            bold: true,
          ),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.bolt_outlined, text: report.cause.label),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.schedule,
            text: 'Signalée ${relativeTime(report.reportedAt)}',
          ),
          if (!ongoing && report.resolvedAt != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.check_circle_outline,
              text: 'Rétablie ${relativeTime(report.resolvedAt)}',
            ),
          ],
          if (report.description != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Text(report.description!),
            ),
          ],
          const SizedBox(height: 24),
          if (ongoing && !isAuthor)
            ElevatedButton.icon(
              onPressed: () async {
                final ok = await provider.confirm(report.id);
                if (context.mounted) {
                  _snack(context,
                      ok ? 'Coupure confirmée.' : 'Échec de la confirmation.');
                }
              },
              icon: const Icon(Icons.thumb_up_outlined),
              label: const Text('Confirmer cette coupure'),
            )
          else if (ongoing && isAuthor)
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await provider.resolve(report.id);
                if (context.mounted) {
                  _snack(context,
                      ok ? 'Coupure marquée rétablie.' : 'Échec de la mise à jour.');
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Marquer rétabli'),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Historique des confirmations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _ConfirmationTimeline(
            reportId: reportId,
            currentUid: provider.currentUid,
            stream: provider.watchConfirmations(reportId),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationTimeline extends StatelessWidget {
  const _ConfirmationTimeline({
    required this.reportId,
    required this.currentUid,
    required this.stream,
  });

  final String reportId;
  final String? currentUid;
  final Stream<List<Confirmation>> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Confirmation>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final confirmations = snapshot.data ?? [];
        if (confirmations.isEmpty) {
          return const Text(
            'Aucune confirmation pour le moment.',
            style: TextStyle(color: AppColors.gray),
          );
        }

        final now = DateTime.now();
        final recent = confirmations
            .where((c) =>
                c.createdAt != null &&
                now.difference(c.createdAt!) < const Duration(hours: 1))
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatPill(
                  value: '${confirmations.length}',
                  label: 'au total',
                ),
                const SizedBox(width: 12),
                _StatPill(
                  value: '$recent',
                  label: 'dernière heure',
                  highlight: recent > 0,
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final c in confirmations)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.how_to_reg,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.userId == currentUid ? 'Vous' : 'Un utilisateur',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      relativeTime(c.createdAt),
                      style: const TextStyle(
                          color: AppColors.gray, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.primary : AppColors.gray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.gray)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.bold = false});

  final IconData icon;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.gray),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ongoing ? Icons.flash_off : Icons.flash_on,
                size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
