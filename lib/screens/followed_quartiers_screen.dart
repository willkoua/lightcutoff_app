import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/confirm_dialog.dart';

/// Gestion des quartiers suivis (alertes de coupures programmées).
///
/// Accessible depuis le Profil. Permet de **se désabonner** d'un quartier même
/// quand aucune coupure programmée n'est affichée pour lui — le bouton
/// « Quartier suivi » de la carte de coupure ne suffisait pas dans ce cas.
class FollowedQuartiersScreen extends StatelessWidget {
  const FollowedQuartiersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final keys = context.select<AuthProvider, List<String>>(
      (a) => a.profile?.followedQuartiers ?? const [],
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.followedTitle)),
      body:
          keys.isEmpty
              ? _EmptyState(l: l)
              : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: keys.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _QuartierTile(followKey: keys[i]),
              ),
    );
  }
}

class _QuartierTile extends StatelessWidget {
  const _QuartierTile({required this.followKey});

  final String followKey;

  /// `REGION|VILLE|QUARTIER` → (titre = quartier, sous-titre = « ville · région »).
  (String, String) _parts() {
    final p = followKey.split('|');
    final region = p.isNotEmpty ? p[0].trim() : '';
    final ville = p.length > 1 ? p[1].trim() : '';
    final quartier = p.length > 2 ? p[2].trim() : '';
    final title =
        quartier.isNotEmpty ? quartier : (ville.isNotEmpty ? ville : followKey);
    final sub = [ville, region].where((s) => s.isNotEmpty).join(' · ');
    return (title, sub);
  }

  Future<void> _unfollow(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await showConfirmDialog(
      context,
      title: l.followedUnfollowConfirmTitle,
      message: l.followedUnfollowConfirmBody,
      confirmLabel: l.followedUnfollowConfirmAction,
    );
    if (!ok || !context.mounted) return;
    await context.read<AuthProvider>().toggleFollowQuartier(followKey);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.followedUnfollowedSnack)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (title, sub) = _parts();
    return ListTile(
      leading: const Icon(Icons.notifications_active, color: AppColors.planned),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: sub.isEmpty ? null : Text(sub),
      trailing: IconButton(
        tooltip: l.followedUnfollowTooltip,
        icon: const Icon(
          Icons.notifications_off_outlined,
          color: AppColors.gray,
        ),
        onPressed: () => _unfollow(context),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_none,
              size: 64,
              color: AppColors.gray,
            ),
            const SizedBox(height: 16),
            Text(
              l.followedEmpty,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              l.followedEmptyHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray),
            ),
          ],
        ),
      ),
    );
  }
}
