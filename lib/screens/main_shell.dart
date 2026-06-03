import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/report_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'report_detail_screen.dart';

/// Conteneur principal de l'app authentifiée : navigation par onglets
/// (Liste / Carte / Profil) via une barre en bas, ce qui décharge l'entête.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // Seul l'onglet actif est monté (pas d'IndexedStack) : la carte
  // (flutter_map + cluster) ne se rend pas correctement si elle est construite
  // hors-écran, donc on la recrée à chaque affichage. L'état métier (coupures,
  // filtres, pagination) vit dans ReportProvider, au-dessus du shell.
  static const _tabs = [HomeScreen(), MapScreen(), ProfileScreen()];

  late final ValueNotifier<String?> _pendingReportId;

  @override
  void initState() {
    super.initState();
    // Écoute des demandes d'ouverture de détail venues d'une notif push.
    // Le push doit se faire depuis ce scope (sous `ReportProvider`).
    _pendingReportId = NotificationService.instance.pendingReportId;
    _pendingReportId.addListener(_consumePendingReport);
    // Cas « app lancée DEPUIS la notif » : la valeur peut déjà être présente
    // avant que le listener ne soit attaché.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _consumePendingReport(),
    );
  }

  @override
  void dispose() {
    _pendingReportId.removeListener(_consumePendingReport);
    super.dispose();
  }

  void _consumePendingReport() {
    final reportId = _pendingReportId.value;
    if (reportId == null || !mounted) return;
    // Reset immédiat pour éviter une double consommation si le listener refire.
    _pendingReportId.value = null;
    // `Navigator.of(context).push` cible le root navigator, dont le subtree
    // n'inclut PAS le `ReportProvider` (scoped sous AuthGate). On ré-injecte
    // l'instance courante via `.value` pour que ReportDetailScreen y accède.
    final reportProvider = context.read<ReportProvider>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ChangeNotifierProvider<ReportProvider>.value(
              value: reportProvider,
              child: ReportDetailScreen(reportId: reportId),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.dark,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.white60,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.list_alt_outlined),
            activeIcon: const Icon(Icons.list_alt),
            label: AppLocalizations.of(context).navList,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.map_outlined),
            activeIcon: const Icon(Icons.map),
            label: AppLocalizations.of(context).navMap,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_circle_outlined),
            activeIcon: const Icon(Icons.account_circle),
            label: AppLocalizations.of(context).navProfile,
          ),
        ],
      ),
    );
  }
}
