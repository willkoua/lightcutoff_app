import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';

/// Ouvre la fenêtre de filtres/recherche (le provider est passé explicitement
/// car le bottom sheet est rendu au-dessus du Navigator racine).
Future<void> showFilterSheet(BuildContext context, ReportProvider provider) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => ChangeNotifierProvider.value(
          value: provider,
          child: const _FilterSheet(),
        ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final TextEditingController _search;

  String _sortLabel(AppLocalizations l, ReportSort s) {
    switch (s) {
      case ReportSort.recent:
        return l.filterSheetSortRecent;
      case ReportSort.active:
        return l.filterSheetSortActive;
      case ReportSort.confirmed:
        return l.filterSheetSortConfirmed;
    }
  }

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: context.read<ReportProvider>().query);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<ReportProvider>();
    final count = p.filteredReports.length;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  l.filterSheetTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (p.hasActiveFilters)
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      p.clearFilters();
                    },
                    child: Text(l.filterSheetReset),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: p.setQuery,
              decoration: InputDecoration(
                hintText: l.filterSheetSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 20),
            _label(l.filterSheetStatusSection),
            Wrap(
              spacing: 8,
              children: [
                _filter(
                  l.statusOngoing,
                  p.statusFilter == OutageStatus.ongoing,
                  () => p.toggleStatusFilter(OutageStatus.ongoing),
                ),
                _filter(
                  l.statusResolved,
                  p.statusFilter == OutageStatus.resolved,
                  () => p.toggleStatusFilter(OutageStatus.resolved),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label(l.filterSheetDisplaySection),
            Wrap(
              spacing: 8,
              children: [
                _filter(l.filterSheetMyReports, p.onlyMine, p.toggleOnlyMine),
                _filter(l.filterSheetNearby, p.nearOnly, () async {
                  final err = await p.setNearOnly(!p.nearOnly);
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(content: Text(appErrorLabel(context, err))),
                      );
                  }
                }),
              ],
            ),
            const SizedBox(height: 16),
            _label(l.filterSheetSortSection),
            Wrap(
              spacing: 8,
              children: [
                for (final s in ReportSort.values)
                  _choice(_sortLabel(l, s), p.sort == s, () => p.setSort(s)),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.filterSheetSeeResults(count)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  Widget _filter(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppColors.primary,
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppColors.primary,
    );
  }
}
