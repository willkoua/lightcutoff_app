import 'package:flutter/material.dart';

import '../providers/report_provider.dart';
import '../screens/profile_screen.dart';
import 'filter_sheet.dart';

/// AppBar commune de l'app.
/// - le bouton **profil** est présent sur toutes les pages (sauf si
///   [showProfile] est désactivé, ex. la page profil elle-même) ;
/// - le bouton **filtre / recherche** n'apparaît que si [filterProvider] est
///   fourni (pages qui listent les coupures : liste et carte).
class NjukaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NjukaAppBar({
    super.key,
    required this.title,
    this.filterProvider,
    this.extraActions = const [],
    this.showProfile = true,
  });

  final String title;
  final ReportProvider? filterProvider;
  final List<Widget> extraActions;
  final bool showProfile;

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
            tooltip: 'Filtrer / rechercher',
            icon: Badge(
              isLabelVisible: filterProvider!.hasActiveFilters,
              smallSize: 9,
              child: const Icon(Icons.tune),
            ),
            onPressed: () => showFilterSheet(context, filterProvider!),
          ),
        if (showProfile)
          IconButton(
            tooltip: 'Mon profil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
          ),
      ],
    );
  }
}
