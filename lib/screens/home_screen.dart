import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../config/utilities.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../providers/official_outage_provider.dart';
import '../providers/region_provider.dart';
import '../providers/report_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../widgets/active_filters_banner.dart';
import '../widgets/service_filter_bar.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/njuka_app_bar.dart';
import '../widgets/official_outages_view.dart';
import '../widgets/report_card.dart';
import '../widgets/service_visuals.dart';
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
  /// Bandeau d'activité désactivé pour le moment — passer à `true` pour le
  /// réafficher (« N coupures actives »).
  static const bool _showActivityBanner = false;

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

    // Le segment « Programmées » est TOUJOURS visible. S'il n'y a pas de
    // fournisseur pour le pays actif, l'onglet affiche un message explicite
    // (au lieu de disparaître en silence) qui invite à vérifier/changer le pays.
    final provider = region.activeProvider;
    final segment = _segment;

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
          // Prompt d'ouverture « Chez toi aussi ? » : sollicitation douce quand
          // une coupure en cours est à < promptRadiusMeters. Une seconde de
          // friction, jamais bloquant, jamais re-montré pour le même report.
          if (segment == HomeSegment.reports && reports.promptCandidate != null)
            _NearbyOutagePrompt(report: reports.promptCandidate!),
          // Bandeau d'activité (inspiré de coupure.ci) : nombre de coupures EN
          // COURS dans le périmètre (pays + service). DÉSACTIVÉ pour le moment
          // (`_showActivityBanner = false`) — remettre à true pour le réactiver.
          if (_showActivityBanner && reports.activeInScopeCount > 0)
            _activityBanner(l, reports.activeInScopeCount),
          // Bannière de périmètre (« Cameroun · À proximité ») AU-DESSUS du
          // filtre service, pour la liste des signalements (cohérent avec la
          // carte). Vide si rien ne restreint l'affichage.
          if (segment == HomeSegment.reports)
            _reportsScopeBanner(context, reports, region, l),
          // Filtre service en TÊTE (Tout / Élec / Eau) : c'est la grille de
          // lecture globale — il s'applique aussi bien aux signalements
          // citoyens (en dessous) qu'aux coupures programmées de l'opérateur.
          const ServiceFilterBar(),
          // Segmented control « Signalements / Programmées » sous le filtre
          // service. Toujours visible ; l'onglet Programmées explique lui-même
          // l'absence de données si le pays n'a pas de fournisseur.
          _SegmentedControl(segment: segment, onChanged: _select),
          Expanded(child: _content(context, reports, provider, segment)),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ReportProvider reports,
    Utility? provider,
    HomeSegment segment,
  ) {
    switch (segment) {
      case HomeSegment.reports:
        return _buildReportsList(context, reports);
      case HomeSegment.planned:
        // Pas de fournisseur pour le pays actif → message explicite + invite à
        // vérifier le pays dans les réglages (au lieu d'un onglet vide muet).
        if (provider == null) {
          final region = context.read<RegionProvider>();
          final country =
              countryLabelForIso(region.activeCountry) ?? region.activeCountry;
          return _Message(
            icon: Icons.event_busy,
            text: AppLocalizations.of(context).plannedNoProviderBody(country),
          );
        }
        final outages = _ensureOutages(provider.country);
        // Propage les filtres globaux (pays + service) au provider one-shot.
        // Si l'utilisateur choisit Eau : pas de CAMWATER ingéré → liste vide.
        final region = context.watch<RegionProvider>();
        if (outages.country != provider.country ||
            outages.serviceFilter != region.serviceFilter) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            outages.setCountry(provider.country);
            outages.setServiceFilter(region.serviceFilter);
          });
        }
        return ChangeNotifierProvider.value(
          value: outages,
          child: const OfficialOutagesView(),
        );
    }
  }

  /// Bandeau d'activité : « N coupures actives » dans le périmètre courant.
  Widget _activityBanner(AppLocalizations l, int count) {
    return Container(
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l.activeOutagesCount(count),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.dark,
            ),
          ),
        ],
      ),
    );
  }

  /// Bannière de périmètre affichée au-dessus du filtre service (liste des
  /// signalements). Vide en cas de chargement / erreur / aucun filtre actif /
  /// liste vide — comme avant, mais positionnée plus haut.
  Widget _reportsScopeBanner(
    BuildContext context,
    ReportProvider reports,
    RegionProvider region,
    AppLocalizations l,
  ) {
    if (reports.loading || reports.error != null) {
      return const SizedBox.shrink();
    }
    final restricted = reports.hasActiveFilters || reports.nearOnly;
    final list = reports.filteredReports;
    if (!restricted || list.isEmpty) return const SizedBox.shrink();
    final scope = buildScopeLabel(
      countryLabel:
          region.worldwide
              ? null
              : (region.activeProvider?.countryLabel ?? region.activeCountry),
      nearOnly: reports.nearOnly,
      nearbyLabel: l.filterSheetNearby,
    );
    return ActiveFiltersBanner(
      count: list.length,
      scope: scope,
      onClear: reports.showAll,
    );
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
    // Périmètre actif (pays + proximité) : sert au choix du message d'état
    // vide. La proximité (`nearOnly`) restreint l'affichage mais n'était pas
    // comptée dans `hasActiveFilters` → on l'ajoute ici. La bannière elle-même
    // est rendue plus haut (au-dessus du filtre service) via _reportsScopeBanner.
    final restricted = reports.hasActiveFilters || reports.nearOnly;
    final list = reports.filteredReports;
    if (list.isEmpty) {
      return _Message(
        icon: restricted ? Icons.search_off : Icons.check_circle_outline,
        text: restricted ? l.homeEmptyWithFilters : l.homeEmptyAllReports,
      );
    }
    return Column(
      children: [
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
          message: confirmOutageBodyLabel(context, report.serviceType),
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
          title: confirmRestoreTitleLabel(context, report.serviceType),
          message: confirmRestoreBodyLabel(context, report.serviceType),
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

/// Prompt d'ouverture « Chez toi aussi ? » (sollicitation douce).
///
/// Affiché en tête de la Liste quand une coupure **en cours** est à moins de
/// [AppConstants.promptRadiusMeters] et que l'utilisateur n'a ni voté ni
/// écarté le prompt. « Oui » = confirmation classique ; « Non » = signal
/// négatif (`denials`, délimite l'emprise) ; ✕ = passer (jamais re-montré).
class _NearbyOutagePrompt extends StatelessWidget {
  const _NearbyOutagePrompt({required this.report});

  final Report report;

  Future<void> _answer(BuildContext context, {required bool affected}) async {
    final l = AppLocalizations.of(context);
    final provider = context.read<ReportProvider>();
    final ok =
        affected
            ? await provider.confirm(report.id)
            : await provider.deny(report.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            affected
                ? (ok ? l.promptNearbySnackYes : l.errorGeneric)
                : l.promptNearbySnackNo,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isWater = report.serviceType == ServiceType.water;
    final color = serviceTypeColor(report.serviceType);
    final heading =
        isWater ? l.promptNearbyHeadingWater : l.promptNearbyHeadingElectricity;
    final noLabel =
        isWater ? l.promptNearbyNoWater : l.promptNearbyNoElectricity;
    final subtitle =
        '${report.location.label} · '
        '${relativeTimeL10n(context, report.reportedAt)} · '
        '${l.reportCardConfirmationsCount(report.confirmationCount)}';

    return Material(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  serviceTypeIcon(report.serviceType),
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    heading,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l.actionCancel,
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.gray,
                  ),
                  onPressed:
                      () => context.read<ReportProvider>().dismissPrompt(
                        report.id,
                      ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.gray, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.promptNearbyQuestion,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _answer(context, affected: true),
                    child: Text(
                      l.promptNearbyYes,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _answer(context, affected: false),
                    child: Text(noLabel, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
