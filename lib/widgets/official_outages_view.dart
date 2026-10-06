import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/official_outage_provider.dart';
import '../theme/app_colors.dart';
import 'official_outage_card.dart';

/// Vue **lecture seule** des coupures planifiées : filtre **région** + filtre
/// **ville** (cascade sous la région) + recherche texte par quartier + liste.
/// Sans Scaffold/AppBar → intégrée dans la Liste (segment « Programmées »).
/// Attend un [OfficialOutageProvider] au-dessus.
class OfficialOutagesView extends StatelessWidget {
  const OfficialOutagesView({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<OfficialOutageProvider>();

    final villes = p.villes;
    final hasRegions = p.regions.isNotEmpty;

    return Column(
      children: [
        if (hasRegions)
          _FilterDropdown(
            icon: Icons.public,
            value: p.region,
            allLabel: l.officialOutagesAllRegions,
            options: p.regions,
            onChanged: p.setRegion,
            topPad: 12,
          ),
        // Filtre ville en cascade sous la région (n'apparaît que s'il y a
        // plusieurs villes dans le périmètre courant).
        if (villes.length > 1)
          _FilterDropdown(
            icon: Icons.location_city,
            value: p.ville,
            allLabel: l.officialOutagesAllVilles,
            options: villes,
            onChanged: p.setVille,
            topPad: hasRegions ? 0 : 12,
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            (hasRegions || villes.length > 1) ? 0 : 12,
            16,
            8,
          ),
          child: TextField(
            onChanged: p.setQuery,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l.officialOutagesSearchHint,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Expanded(child: _body(context, p, l)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    OfficialOutageProvider p,
    AppLocalizations l,
  ) {
    if (p.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (p.hasError) {
      return _EmptyState(
        icon: Icons.cloud_off_outlined,
        text: l.officialOutagesError,
        onRetry: p.load,
        retryLabel: l.actionRetry,
      );
    }
    final items = p.filtered;
    if (items.isEmpty) {
      return _EmptyState(
        icon: Icons.event_busy_outlined,
        text: l.officialOutagesEmpty,
      );
    }
    return RefreshIndicator(
      onRefresh: p.load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: items.length,
        itemBuilder: (_, i) => OfficialOutageCard(outage: items[i]),
      ),
    );
  }
}

/// Dropdown de filtre (région ou ville) avec une option « tout » en tête.
class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.value,
    required this.allLabel,
    required this.options,
    required this.onChanged,
    required this.topPad,
  });

  final IconData icon;
  final String? value;
  final String allLabel;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final double topPad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPad, 16, 8),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
          for (final o in options)
            DropdownMenuItem<String?>(value: o, child: Text(o)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.text,
    this.onRetry,
    this.retryLabel,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.gray),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: AppColors.gray)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(retryLabel ?? 'Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
