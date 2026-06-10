import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/report.dart';
import '../providers/official_outage_provider.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../widgets/njuka_app_bar.dart';
import '../widgets/official_outage_card.dart';
import '../widgets/official_outages_view.dart';
import '../widgets/report_card.dart';
import 'report_detail_screen.dart';
import 'report_form_screen.dart';

/// Segment de la Liste : tout / signalements communautaires / coupures planifiées.
enum HomeSegment { all, reports, planned }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeSegment _segment = HomeSegment.reports;

  // Créé en lazy au 1ᵉʳ passage sur « Programmées » / « Toutes » (charge alors).
  OfficialOutageProvider? _outages;

  OfficialOutageProvider _ensureOutages() =>
      _outages ??= OfficialOutageProvider();

  @override
  void dispose() {
    _outages?.dispose();
    super.dispose();
  }

  void _select(HomeSegment s) {
    if (s != HomeSegment.reports) _ensureOutages();
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
    final l = AppLocalizations.of(context);

    return Scaffold(
      // Le filtre signalements n'a de sens que sur les segments « Signalements »
      // et « Toutes » (les programmées ont leur propre recherche/région).
      appBar: NjukaAppBar(
        title: l.homeTitle,
        filterProvider: _segment == HomeSegment.planned ? null : reports,
      ),
      floatingActionButton:
          _segment == HomeSegment.planned
              ? null
              : FloatingActionButton.extended(
                onPressed: () => _open(context, const ReportFormScreen(), reports),
                icon: const Icon(Icons.add),
                label: Text(l.actionSignal),
              ),
      body: Column(
        children: [
          _SegmentedControl(segment: _segment, onChanged: _select),
          Expanded(child: _content(context, reports, l)),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ReportProvider reports,
    AppLocalizations l,
  ) {
    switch (_segment) {
      case HomeSegment.reports:
        return _buildReportsList(context, reports);
      case HomeSegment.planned:
        return ChangeNotifierProvider.value(
          value: _ensureOutages(),
          child: const OfficialOutagesView(),
        );
      case HomeSegment.all:
        return ChangeNotifierProvider.value(
          value: _ensureOutages(),
          child: _AllView(reports: reports, card: _reportCard),
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
      HomeSegment.all: l.homeSegmentAll,
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

/// Segment « Toutes » : section « En cours » (signalements) puis « À venir » (Eneo).
class _AllView extends StatelessWidget {
  const _AllView({required this.reports, required this.card});

  final ReportProvider reports;
  final Widget Function(BuildContext, ReportProvider, Report) card;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final outages = context.watch<OfficialOutageProvider>();
    final ongoing = reports.filteredReports;
    final planned = outages.filtered;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([reports.refresh(), outages.load()]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 88),
        children: [
          _SectionHeader(
            icon: Icons.flash_on,
            color: AppColors.ongoing,
            label: l.statusOngoing,
          ),
          if (ongoing.isEmpty)
            _hint(l.homeEmptyAllReports)
          else
            for (final r in ongoing) card(context, reports, r),
          _SectionHeader(
            icon: Icons.engineering_outlined,
            color: AppColors.planned,
            label: l.homeSectionUpcoming,
          ),
          if (outages.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (planned.isEmpty)
            _hint(l.officialOutagesEmpty)
          else
            for (final o in planned) OfficialOutageCard(outage: o),
        ],
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Text(text, style: const TextStyle(color: AppColors.gray)),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: color.withValues(alpha: 0.25))),
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
