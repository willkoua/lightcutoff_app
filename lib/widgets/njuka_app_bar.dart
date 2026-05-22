import 'package:flutter/material.dart';

import '../providers/report_provider.dart';
import 'filter_sheet.dart';

/// AppBar commune de l'app. Le bouton **filtre / recherche** n'apparaît que si
/// [filterProvider] est fourni (pages qui listent les coupures : Liste et Carte).
/// La navigation (Liste / Carte / Profil) est portée par la barre du bas
/// (`MainShell`), pas par l'entête.
class NjukaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NjukaAppBar({super.key, required this.title, this.filterProvider});

  final String title;
  final ReportProvider? filterProvider;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: [
        if (filterProvider != null)
          IconButton(
            tooltip: 'Filtrer / rechercher',
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
