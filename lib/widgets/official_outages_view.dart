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
class OfficialOutagesView extends StatefulWidget {
  const OfficialOutagesView({super.key});

  @override
  State<OfficialOutagesView> createState() => _OfficialOutagesViewState();
}

class _OfficialOutagesViewState extends State<OfficialOutagesView> {
  /// Panneau de filtres replié par défaut (discret) ; l'utilisateur le déplie
  /// via la barre « Filtrer ». La liste occupe l'espace le reste du temps.
  bool _open = false;

  /// Contrôleur de la recherche : conserve le texte saisi quand on replie puis
  /// rouvre le panneau (sinon le champ réapparaîtrait vide malgré le filtre).
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<OfficialOutageProvider>();

    // Garde le champ aligné sur l'état du provider (ex. après un « Effacer »),
    // sans sauter le curseur pendant la frappe (texte déjà égal → no-op).
    if (_searchCtrl.text != p.query) {
      _searchCtrl.value = TextEditingValue(
        text: p.query,
        selection: TextSelection.collapsed(offset: p.query.length),
      );
    }

    final villes = p.villes;
    final hasRegions = p.regions.isNotEmpty;
    final active =
        (p.region != null ? 1 : 0) +
        (p.ville != null ? 1 : 0) +
        (p.query.trim().isNotEmpty ? 1 : 0);

    return Column(
      children: [
        // Barre compacte « Filtrer » : masque le panneau par défaut, pastille
        // si des filtres sont actifs, chevron qui tourne.
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 18, color: AppColors.gray),
                const SizedBox(width: 8),
                Text(
                  l.officialOutagesFilter,
                  style: const TextStyle(
                    color: AppColors.gray,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (active > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$active',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (active > 0 && !_open)
                  TextButton(
                    onPressed: () {
                      p.setRegion(null);
                      p.setVille(null);
                      p.setQuery('');
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l.officialOutagesClearFilters),
                  ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(
                    Icons.expand_more,
                    size: 22,
                    color: AppColors.gray,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          if (hasRegions)
            _FilterDropdown(
              icon: Icons.public,
              value: p.region,
              allLabel: l.officialOutagesAllRegions,
              options: p.regions,
              onChanged: p.setRegion,
              topPad: 0,
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
              topPad: 0,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
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
        ],
        const Divider(height: 1),
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
