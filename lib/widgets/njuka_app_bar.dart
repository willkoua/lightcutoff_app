import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../providers/report_provider.dart';
import 'filter_sheet.dart';

/// AppBar commune de l'app. Le bouton **filtre / recherche** n'apparaît que si
/// [filterProvider] est fourni (pages qui listent les coupures : Liste et Carte).
/// La navigation (Liste / Carte / Profil) est portée par la barre du bas
/// (`MainShell`), pas par l'entête. L'accès aux Paramètres vit dans l'AppBar
/// de Profil (cf. `profile_screen.dart`).
class NjukaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NjukaAppBar({
    super.key,
    required this.title,
    this.filterProvider,
    this.extraActions = const [],
  });

  final String title;
  final ReportProvider? filterProvider;

  /// Actions ajoutées avant le bouton filtre (ex. accès « Coupures planifiées »).
  final List<Widget> extraActions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: [
        ...extraActions,
        if (filterProvider != null)
          IconButton(
            tooltip: AppLocalizations.of(context).tooltipFilter,
            icon: Badge(
              isLabelVisible: filterProvider!.hasActiveFilters,
              smallSize: 9,
              child: const Icon(Icons.tune),
            ),
            onPressed: () => showFilterSheet(context, filterProvider!),
          ),
      ],
    );
  }
}
