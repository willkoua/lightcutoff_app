import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../config/electricity_providers.dart';
import '../models/report.dart';
import '../providers/official_outage_provider.dart';
import '../providers/region_provider.dart';
import '../providers/report_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/njuka_app_bar.dart';
import '../widgets/official_outages_view.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';
import 'report_form_screen.dart';

/// Segment de la Liste : signalements communautaires / coupures planifiées.
enum HomeSegment { reports, planned }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeSegment _segment = HomeSegment.reports;

  // Créé en lazy au 1ᵉʳ passage sur « Programmées » / « Toutes » (charge alors).
  OfficialOutageProvider? _outages;

  OfficialOutageProvider _ensureOutages(String country) =>
      _outages ??= OfficialOutageProvider(country: country);

  @override
  void dispose() {
    _outages?.dispose();
    super.dispose();
  }

  void _select(HomeSegment s) {
    if (s == HomeSegment.planned && _segment != HomeSegment.planned) {
      AnalyticsService.instance.logPlannedOutagesViewed();
    }
    setState(() => _segment = s);
  }

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
    final region = context.watch<RegionProvider>();
    final l = AppLocalizations.of(context);

    // Pas de fournisseur pour le pays de l'utilisateur → on masque carrément le
    // segment « Programmées » (et le sélecteur), et on reste sur les signalements.
    final provider = region.activeProvider;
    final showPlanned = provider != null;
    final segment = showPlanned ? _segment : HomeSegment.reports;

    return Scaffold(
      appBar: NjukaAppBar(
        title: l.homeTitle,
        filterProvider: segment == HomeSegment.planned ? null : reports,
      ),
      floatingActionButton:
          segment == HomeSegment.planned
              ? null
              : FloatingActionButton.extended(
                onPressed: () => _open(context, const ReportFormScreen(), reports),
                icon: const Icon(Icons.add),
                label: Text(l.actionSignal),
              ),
      body: Column(
        children: [
          if (showPlanned)
            _SegmentedControl(segment: segment, onChanged: _select),
          Expanded(child: _content(context, reports, provider, segment)),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ReportProvider reports,
    ElectricityProvider? provider,
    HomeSegment segment,
  ) {
    switch (segment) {
      case HomeSegment.reports:
        return _buildReportsList(context, reports);
      case HomeSegment.planned:
        // `segment == planned` ⇒ `showPlanned` ⇒ provider non nul.
        final outages = _ensureOutages(provider!.country);
        // Si le pays actif change (override dev / profil), re-requête après frame.
        if (outages.country != provider.country) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) outages.setCountry(provider.country);
          });
        }
        return ChangeNotifierProvider.value(
          value: outages,
          child: const OfficialOutagesView(),
        );
    }
  }

  // --- Liste des signalements (comportement existant) -----------------------

  Widget _buildReportsList(BuildContext context, ReportProvider reports) {
    final l = AppLocalizations.of(context);
    if (reports.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (reports.error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: appErrorLabel(context, reports.error!),
      );
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
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 88),
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == list.length) {
                  final canLoadMore =
                      reports.hasMore &&
                      !reports.nearOnly &&
                      !reports.hasActiveFilters;
                  if (!canLoadMore) return const SizedBox(height: 8);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => reports.loadMore(),
                  );
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _reportCard(context, reports, list[i]);
              },
            ),
          ),
        ),
      ],
    );
  }

  // Carte signalement + ses actions — factorisée (liste « Signalements » et « Toutes »).
  Widget _reportCard(
    BuildContext context,
    ReportProvider reports,
    Report report,
  ) {
    final l = AppLocalizations.of(context);
    return ReportCard(
      report: report,
      isAuthor: reports.isAuthor(report),
      alreadyConfirmed: reports.iConfirmed(report.id),
      alreadyRestored: reports.iRestored(report.id),
      onTap:
          () => _open(
            context,
            ReportDetailScreen(reportId: report.id),
            reports,
          ),
      onConfirm: () async {
        final go = await showConfirmDialog(
          context,
          title: l.confirmOutageTitle,
          message: l.confirmOutageBody,
          confirmLabel: l.actionConfirm,
        );
        if (!go || !context.mounted) return;
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
        final go = await showConfirmDialog(
          context,
          title: l.confirmRestoreTitle,
          message: l.confirmRestoreBody,
          confirmLabel: l.confirmRestoreAction,
        );
        if (!go || !context.mounted) return;
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
  }
}

/// Sélecteur segmenté Toutes / Signalements / Programmées.
class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({required this.segment, required this.onChanged});

  final HomeSegment segment;
  final ValueChanged<HomeSegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = {
      HomeSegment.reports: l.homeSegmentReports,
      HomeSegment.planned: l.homeSegmentPlanned,
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFE7E7EA),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          for (final s in HomeSegment.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: s == segment ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labels[s]!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: s == segment ? Colors.white : AppColors.gray,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
