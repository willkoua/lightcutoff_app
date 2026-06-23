import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_constants.dart';
import '../config/electricity_providers.dart';
import '../models/report.dart';
import '../providers/official_outage_provider.dart';
import '../providers/region_provider.dart';
import '../providers/report_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../widgets/active_filters_banner.dart';
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
                onPressed: () => showReportFormSheet(context, reports),
                icon: const Icon(Icons.add),
                label: Text(l.actionSignal),
              ),
      body: Column(
        children: [
          const _SurveyBanner(),
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
    final region = context.watch<RegionProvider>();
    // Périmètre actif (pays + proximité) : sert à la bannière et au choix du
    // message d'état vide. La proximité (`nearOnly`) restreint l'affichage mais
    // n'était pas comptée dans `hasActiveFilters` → on l'ajoute ici.
    final restricted = reports.hasActiveFilters || reports.nearOnly;
    final scope = buildScopeLabel(
      countryLabel:
          region.worldwide
              ? null
              : (region.activeProvider?.countryLabel ?? region.activeCountry),
      nearOnly: reports.nearOnly,
      nearbyLabel: l.filterSheetNearby,
    );
    final list = reports.filteredReports;
    if (list.isEmpty) {
      return _Message(
        icon: restricted ? Icons.search_off : Icons.check_circle_outline,
        text: restricted ? l.homeEmptyWithFilters : l.homeEmptyAllReports,
      );
    }
    return Column(
      children: [
        if (restricted)
          ActiveFiltersBanner(
            count: list.length,
            scope: scope,
            onClear: reports.showAll,
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
          () =>
              _open(context, ReportDetailScreen(reportId: report.id), reports),
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

/// Bannière (fermable) invitant les testeurs à répondre au sondage. Affichée
/// **uniquement en dev/staging** (`showDevTools`) et tant qu'elle n'a pas été
/// fermée (état persisté). N'apparaît jamais en prod.
class _SurveyBanner extends StatefulWidget {
  const _SurveyBanner();

  @override
  State<_SurveyBanner> createState() => _SurveyBannerState();
}

class _SurveyBannerState extends State<_SurveyBanner> {
  static const _prefKey = 'survey_banner_dismissed';
  bool _dismissed = true; // masqué tant qu'on n'a pas lu la préférence

  @override
  void initState() {
    super.initState();
    if (AppConfig.showDevTools) _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _dismissed = prefs.getBool(_prefKey) ?? false);
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }

  Future<void> _open() async {
    try {
      await launchUrl(
        Uri.parse(AppConstants.surveyUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      /* lien non critique */
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.showDevTools || _dismissed) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(
                Icons.assignment_outlined,
                size: 20,
                color: AppColors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.surveyBannerText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
              ),
              IconButton(
                tooltip: l.surveyBannerDismiss,
                icon: const Icon(Icons.close, size: 18, color: AppColors.gray),
                onPressed: _dismiss,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
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
                    color:
                        s == segment ? AppColors.primary : Colors.transparent,
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
