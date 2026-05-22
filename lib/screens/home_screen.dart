import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/njuka_app_bar.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';
import 'report_form_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(BuildContext context, Widget child, ReportProvider provider) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChangeNotifierProvider.value(value: provider, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = context.watch<ReportProvider>();
    return Scaffold(
      appBar: NjukaAppBar(
        title: 'Coupures signalées',
        filterProvider: reports,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, const ReportFormScreen(), reports),
        icon: const Icon(Icons.add),
        label: const Text('Signaler'),
      ),
      body: _buildList(context, reports),
    );
  }

  Widget _buildList(BuildContext context, ReportProvider reports) {
    if (reports.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (reports.error != null) {
      return _Message(icon: Icons.error_outline, text: reports.error!);
    }
    final list = reports.filteredReports;
    if (list.isEmpty) {
      return _Message(
        icon:
            reports.hasActiveFilters
                ? Icons.search_off
                : Icons.check_circle_outline,
        text:
            reports.hasActiveFilters
                ? 'Aucune coupure ne correspond à votre recherche.'
                : 'Aucune coupure signalée pour le moment.',
      );
    }
    return Column(
      children: [
        if (reports.hasActiveFilters)
          _ActiveFiltersBanner(
            count: list.length,
            onClear: reports.clearFilters,
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 88),
            // +1 pour le pied de liste (indicateur « charger plus »).
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == list.length) {
                // Pagination désactivée tant qu'un filtre est actif : le
                // filtrage en mémoire rendrait le « charger plus » ambigu.
                final canLoadMore = reports.hasMore && !reports.hasActiveFilters;
                if (!canLoadMore) return const SizedBox(height: 8);
                // Déclenche le chargement quand le pied entre à l'écran.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => reports.loadMore(),
                );
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final report = list[i];
              return ReportCard(
                report: report,
                isAuthor: reports.isAuthor(report),
                onTap:
                    () => _open(
                      context,
                      ReportDetailScreen(reportId: report.id),
                      reports,
                    ),
                onConfirm: () async {
                  final ok = await reports.confirm(report.id);
                  if (context.mounted) {
                    _snack(
                      context,
                      ok ? 'Coupure confirmée.' : 'Échec de la confirmation.',
                    );
                  }
                },
                onResolve: () async {
                  final ok = await reports.resolve(report.id);
                  if (context.mounted) {
                    _snack(
                      context,
                      ok
                          ? 'Coupure marquée rétablie.'
                          : 'Échec de la mise à jour.',
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActiveFiltersBanner extends StatelessWidget {
  const _ActiveFiltersBanner({required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            'Filtres actifs · $count résultat${count > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClear,
            child: const Text(
              'Effacer',
              style: TextStyle(
                color: AppColors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.gray),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray),
            ),
          ],
        ),
      ),
    );
  }
}
