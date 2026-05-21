import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/report_card.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'report_detail_screen.dart';
import 'report_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(Widget child, ReportProvider provider) {
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
      appBar: AppBar(
        title: const Text('Coupures signalées'),
        actions: [
          IconButton(
            tooltip: 'Voir sur la carte',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => _open(const MapScreen(), reports),
          ),
          IconButton(
            tooltip: 'Mon profil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const ReportFormScreen(), reports),
        icon: const Icon(Icons.add),
        label: const Text('Signaler'),
      ),
      body: Column(
        children: [
          _FilterBar(
            controller: _searchController,
            provider: reports,
            onNearError: _snack,
          ),
          Expanded(child: _buildList(reports)),
        ],
      ),
    );
  }

  Widget _buildList(ReportProvider reports) {
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
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final report = list[i];
        return ReportCard(
          report: report,
          isAuthor: reports.isAuthor(report),
          onTap: () => _open(ReportDetailScreen(reportId: report.id), reports),
          onConfirm: () async {
            final ok = await reports.confirm(report.id);
            if (mounted) {
              _snack(ok ? 'Coupure confirmée.' : 'Échec de la confirmation.');
            }
          },
          onResolve: () async {
            final ok = await reports.resolve(report.id);
            if (mounted) {
              _snack(
                ok ? 'Coupure marquée rétablie.' : 'Échec de la mise à jour.',
              );
            }
          },
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.provider,
    required this.onNearError,
  });

  final TextEditingController controller;
  final ReportProvider provider;
  final void Function(String message) onNearError;

  static const _sortLabels = {
    ReportSort.recent: 'Récentes',
    ReportSort.active: 'Actives',
    ReportSort.confirmed: 'Confirmées',
  };

  @override
  Widget build(BuildContext context) {
    final count = provider.filteredReports.length;
    return Material(
      color: AppColors.dark,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Column(
          children: [
            TextField(
              controller: controller,
              onChanged: provider.setQuery,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Rechercher une zone…',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon:
                    provider.query.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () {
                            controller.clear();
                            provider.setQuery('');
                          },
                        ),
                isDense: true,
                fillColor: Colors.white10,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(
                    'En cours',
                    provider.statusFilter == OutageStatus.ongoing,
                    () => provider.toggleStatusFilter(OutageStatus.ongoing),
                  ),
                  _chip(
                    'Rétabli',
                    provider.statusFilter == OutageStatus.resolved,
                    () => provider.toggleStatusFilter(OutageStatus.resolved),
                  ),
                  _chip(
                    'Mes signalements',
                    provider.onlyMine,
                    provider.toggleOnlyMine,
                  ),
                  _chip('À proximité', provider.nearOnly, () async {
                    final err = await provider.setNearOnly(!provider.nearOnly);
                    if (err != null) onNearError(err);
                  }),
                  _causeMenu(),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '$count résultat${count > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const Spacer(),
                if (provider.hasActiveFilters)
                  TextButton(
                    onPressed: () {
                      controller.clear();
                      provider.clearFilters();
                    },
                    child: const Text('Effacer'),
                  ),
                _sortMenu(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        backgroundColor: Colors.white10,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? AppColors.dark : AppColors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        side: BorderSide.none,
      ),
    );
  }

  Widget _causeMenu() {
    final cause = provider.causeFilter;
    return PopupMenuButton<OutageCause?>(
      onSelected: provider.setCauseFilter,
      itemBuilder:
          (_) => [
            const PopupMenuItem(value: null, child: Text('Toutes les causes')),
            ...OutageCause.values.map(
              (c) => PopupMenuItem(value: c, child: Text(c.label)),
            ),
          ],
      child: Chip(
        backgroundColor: cause != null ? AppColors.primary : Colors.white10,
        label: Text(
          cause?.label ?? 'Cause',
          style: TextStyle(
            color: cause != null ? AppColors.dark : AppColors.white,
          ),
        ),
        avatar: Icon(
          Icons.expand_more,
          size: 18,
          color: cause != null ? AppColors.dark : AppColors.white,
        ),
        side: BorderSide.none,
      ),
    );
  }

  Widget _sortMenu() {
    return PopupMenuButton<ReportSort>(
      onSelected: provider.setSort,
      itemBuilder:
          (_) =>
              ReportSort.values
                  .map(
                    (s) =>
                        PopupMenuItem(value: s, child: Text(_sortLabels[s]!)),
                  )
                  .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sort, size: 18, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            _sortLabels[provider.sort]!,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
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
