import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/region_provider.dart';
import '../providers/stats_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_colors.dart';
import '../utils/outage_stats.dart';
import '../widgets/service_filter_bar.dart';

/// Écran « Mes statistiques » : agrégats perso (mes coupures) et de zone.
/// Aucune prédiction — uniquement la donnée déjà collectée, rendue lisible.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late final StatsProvider _provider = StatsProvider();

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logStatsViewed();
    final uid = context.read<AuthProvider>().profile?.uid;
    if (uid != null) _provider.load(uid);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final uid = context.read<AuthProvider>().profile?.uid;
    if (uid != null) await _provider.load(uid);
  }

  /// Enveloppe une section dans une vue scrollable + pull-to-refresh (un par
  /// onglet).
  Widget _scrollable(Widget child) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [child],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Filtre service global (Tout / Élec / Eau) : on respecte le même choix
    // que la liste/carte (segmented control commun + persistance partagée).
    final serviceFilter = context.watch<RegionProvider>().serviceFilter;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.statsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l.statsSectionMine),
              Tab(text: l.statsSectionZone),
            ],
          ),
        ),
        body: Column(
          children: [
            // Sélecteur de service commun : pose la même grille de lecture que
            // la liste/carte → si l'utilisateur consulte « Eau », il voit ses
            // stats eau, sa zone eau. Recalcul à la volée, pas de rechargement.
            const ServiceFilterBar(),
            Expanded(
              child: ListenableBuilder(
                listenable: _provider,
                builder: (context, _) {
                  switch (_provider.status) {
                    case StatsStatus.loading:
                      return const Center(child: CircularProgressIndicator());
                    case StatsStatus.error:
                      return _ErrorState(
                        message: l.statsError,
                        onRetry: _refresh,
                      );
                    case StatsStatus.ready:
                      return TabBarView(
                        children: [
                          _scrollable(
                            _Section(
                              stats: _provider.mineFor(serviceFilter),
                              emptyText: l.statsEmptyMine,
                            ),
                          ),
                          _scrollable(
                            _Section(
                              subtitle: l.statsZoneHint,
                              stats: _provider.zoneFor(serviceFilter),
                              emptyText: l.statsEmptyZone,
                              unavailable: _provider.zoneUnavailable,
                              unavailableText: l.statsZoneUnavailable,
                            ),
                          ),
                        ],
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une section (« mes coupures » ou « ma zone ») : titre + soit l'état vide /
/// indisponible, soit les cartes chiffrées et les histogrammes.
class _Section extends StatelessWidget {
  const _Section({
    required this.stats,
    required this.emptyText,
    this.subtitle,
    this.unavailable = false,
    this.unavailableText,
  });

  final String? subtitle;
  final OutageStats? stats;
  final String emptyText;
  final bool unavailable;
  final String? unavailableText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              subtitle!,
              style: const TextStyle(color: AppColors.gray, fontSize: 13),
            ),
          ),
        const SizedBox(height: 12),
        if (unavailable)
          _Hint(icon: Icons.location_off_outlined, text: unavailableText ?? '')
        else if (stats == null || stats!.isEmpty)
          _Hint(icon: Icons.insights_outlined, text: emptyText)
        else
          _Body(stats: stats!, l: l),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats, required this.l});

  final OutageStats stats;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final avg = stats.averageResolvedDuration;
    final peakHour = stats.peakHour;
    final peakDay = stats.peakWeekday;
    return Column(
      children: [
        Row(
          children: [
            _StatCard(value: '${stats.total}', label: l.statsTotal),
            const SizedBox(width: 10),
            _StatCard(value: '${stats.ongoingCount}', label: l.statsOngoing),
            const SizedBox(width: 10),
            _StatCard(value: '${stats.resolvedCount}', label: l.statsResolved),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StatCard(
              value: avg == null ? '—' : _formatDuration(l, avg),
              label: l.statsAvgDuration,
            ),
            const SizedBox(width: 10),
            _StatCard(
              value: _formatDuration(l, stats.totalResolvedDuration),
              label: l.statsTotalDuration,
            ),
          ],
        ),
        if (peakHour != null || peakDay != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (peakHour != null)
                _StatCard(
                  value: l.statsHourLabel(peakHour),
                  label: l.statsPeakHour,
                ),
              if (peakHour != null && peakDay != null)
                const SizedBox(width: 10),
              if (peakDay != null)
                _StatCard(
                  value: _weekdayShort(context, peakDay),
                  label: l.statsPeakDay,
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _BarChart(
          title: l.statsByHour,
          values: stats.byHour,
          labelFor: (i) => i % 6 == 0 ? '$i' : '',
        ),
        const SizedBox(height: 20),
        _BarChart(
          title: l.statsByWeekday,
          values: stats.byWeekday,
          labelFor: (i) => _weekdayShort(context, i),
        ),
      ],
    );
  }
}

/// Carte chiffrée compacte (extensible sur la largeur de la rangée).
class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Histogramme à barres verticales, 100 % maison (pas de dépendance chart).
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.title,
    required this.values,
    required this.labelFor,
  });

  final String title;
  final List<int> values;
  final String Function(int index) labelFor;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(0, (m, v) => v > m ? v : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FractionallySizedBox(
                          heightFactor:
                              maxValue == 0 ? 0 : values[i] / maxValue,
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              color:
                                  values[i] == 0
                                      ? AppColors.gray.withValues(alpha: 0.15)
                                      : AppColors.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        labelFor(i),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.gray,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.gray.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gray, size: 36),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.gray),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.gray),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.gray)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: Text(l.actionRetry)),
        ],
      ),
    );
  }
}

/// Durée formatée façon « 3 h 20 min » / « 45 min », via l10n.
String _formatDuration(AppLocalizations l, Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? l.statsDurationHm(h, m) : l.statsDurationM(m);
}

/// Nom court du jour (0 = lundi … 6 = dimanche) dans la locale courante.
String _weekdayShort(BuildContext context, int index) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  // 2024-01-01 est un lundi → +index donne le bon jour de semaine.
  final day = DateTime(2024, 1, 1 + index);
  return DateFormat.E(locale).format(day);
}
