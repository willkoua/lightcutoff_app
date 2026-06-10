import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/official_outage_provider.dart';
import '../theme/app_colors.dart';
import 'official_outage_card.dart';

/// Vue **lecture seule** des coupures planifiées (Eneo) : recherche par quartier
/// + filtre région + liste. Sans Scaffold/AppBar → intégrée dans la Liste
/// (segment « Programmées »). Attend un [OfficialOutageProvider] au-dessus.
class OfficialOutagesView extends StatelessWidget {
  const OfficialOutagesView({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<OfficialOutageProvider>();

    return Column(
      children: [
        if (p.regions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<String?>(
              value: p.region,
              isExpanded: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.public),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l.officialOutagesAllRegions),
                ),
                for (final r in p.regions)
                  DropdownMenuItem<String?>(value: r, child: Text(r)),
              ],
              onChanged: p.setRegion,
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, p.regions.isEmpty ? 12 : 0, 16, 8),
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
