import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: NjukaAppBar(title: l.homeTitle, filterProvider: reports),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, const ReportFormScreen(), reports),
        icon: const Icon(Icons.add),
        label: Text(l.actionSignal),
      ),
      body: _buildList(context, reports),
    );
  }

  Widget _buildList(BuildContext context, ReportProvider reports) {
    final l = AppLocalizations.of(context);
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
                ? l.homeEmptyWithFilters
                : l.homeEmptyAllReports,
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
          child: RefreshIndicator(
            onRefresh: reports.refresh,
            child: ListView.builder(
              // Toujours défilable pour permettre le tirer-pour-rafraîchir.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 88),
              // +1 pour le pied de liste (indicateur « charger plus »).
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == list.length) {
                  // Pagination désactivée en mode proximité (résultats bornés,
                  // non paginés) ou tant qu'un filtre en mémoire est actif.
                  final canLoadMore =
                      reports.hasMore &&
                      !reports.nearOnly &&
                      !reports.hasActiveFilters;
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
                        ok
                            ? l.reportDetailSnackConfirmed
                            : l.reportDetailSnackConfirmFailed,
                      );
                    }
                  },
                  onMarkRestored: () async {
                    final ok = await reports.markRestored(report.id);
                    if (context.mounted) {
                      _snack(
                        context,
                        ok
                            ? l.reportDetailSnackRestoredOk
                            : l.reportDetailSnackRestoredFailed,
                      );
                    }
                  },
                );
              },
            ),
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
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.homeActiveFilters(count),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Text(
              l.homeClearFilters,
              style: const TextStyle(
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
