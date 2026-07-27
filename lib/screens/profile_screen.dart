import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/anonymous_activity.dart';
import '../utils/formatting.dart';
import '../utils/l10n_helpers.dart';
import 'account_security_screen.dart';
import 'edit_profile_screen.dart';
import 'followed_quartiers_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'upgrade_account_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final isAnonymous = auth.isAnonymous;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        // « Profil » seulement pour un compte réel ; « Compte » en session
        // anonyme (l'écran montre alors le mur d'upgrade, pas un profil).
        title: Text(isAnonymous ? l.profileTitleAnonymous : l.profileTitle),
        actions: [
          if (profile != null)
            IconButton(
              tooltip: l.profileTooltipEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ),
            ),
          // Paramètres TOUJOURS accessibles, y compris en session anonyme :
          // langue, légal, env dev, "Effacer cette session" → décision pivot
          // 2026-06-24, on ne bloque pas l'accès aux réglages derrière l'upgrade.
          IconButton(
            tooltip: l.profileTooltipSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
          ),
        ],
      ),
      body:
          isAnonymous
              ? const _UpgradeWall()
              : profile == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 8),
                  _Avatar(name: profile.fullName),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      profile.fullName.isEmpty ? '—' : profile.fullName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (profile.username.isNotEmpty)
                    Center(
                      child: Text(
                        '@${profile.username}',
                        style: const TextStyle(color: AppColors.gray),
                      ),
                    ),
                  Center(
                    child: Text(
                      profile.email,
                      style: const TextStyle(color: AppColors.gray),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _InfoTile(
                    icon: Icons.cake_outlined,
                    label: l.profileBirthDate,
                    value:
                        profile.birthDate != null
                            ? formatDate(profile.birthDate!)
                            : l.profileBirthDateMissing,
                  ),
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: l.profilePhone,
                    value:
                        profile.phoneNumber?.isNotEmpty == true
                            ? profile.phoneNumber!
                            : l.profilePhoneMissing,
                  ),
                  _InfoTile(
                    icon: Icons.place_outlined,
                    label: l.profileResidence,
                    value:
                        profile.homeLocation.label.isEmpty
                            ? l.profileResidenceMissing
                            : profile.homeLocation.label,
                  ),
                  _InfoTile(
                    icon: Icons.event_outlined,
                    label: l.profileMemberSince,
                    value:
                        profile.createdAt != null
                            ? relativeTimeL10n(context, profile.createdAt)
                            : '—',
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.insights_outlined,
                      color: AppColors.gray,
                    ),
                    title: Text(l.profileStatsTitle),
                    subtitle: Text(
                      l.profileStatsSubtitle,
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 13,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StatsScreen(),
                          ),
                        ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.gray,
                    ),
                    title: Text(l.profileFollowedTitle),
                    subtitle: Text(
                      l.profileFollowedSubtitle,
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 13,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FollowedQuartiersScreen(),
                          ),
                        ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.gray,
                    ),
                    title: Text(l.profileSecurityTitle),
                    subtitle: Text(
                      l.profileSecuritySubtitle,
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 13,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccountSecurityScreen(),
                          ),
                        ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.read<AuthProvider>().logout(),
                    icon: const Icon(Icons.logout, color: AppColors.orange),
                    label: Text(
                      l.profileLogoutButton,
                      style: const TextStyle(color: AppColors.orange),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: AppColors.orange),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials =
        name.trim().isEmpty
            ? '?'
            : name
                .trim()
                .split(RegExp(r'\s+'))
                .take(2)
                .map((w) => w[0].toUpperCase())
                .join();
    return Center(
      child: CircleAvatar(
        radius: 44,
        backgroundColor: AppColors.primary,
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.dark,
          ),
        ),
      ),
    );
  }
}

/// Mur d'upgrade affiché à la place du profil pour une session anonyme.
/// 2 CTA : « Créer un compte » (→ [UpgradeAccountScreen] via
/// `linkWithCredential`, préserve l'historique anonyme) et « J'ai déjà un
/// compte » (→ [LoginScreen], **après confirmation** : on perd l'historique
/// car Firebase ne fusionne pas deux uid).
class _UpgradeWall extends StatelessWidget {
  const _UpgradeWall();

  Future<void> _confirmLoginSwitch(BuildContext context) async {
    final l = AppLocalizations.of(context);
    // L'avertissement « tes signalements/votes anonymes ne seront pas
    // rattachés » n'a de sens que si la session anonyme a réellement produit
    // du contenu. Un utilisateur neuf va directement à la connexion (zéro
    // friction sur le chemin principal — décision 2026-07-25).
    final hasActivity = await anonymousSessionHasActivity(
      FirebaseAuth.instance.currentUser,
    );
    if (!context.mounted) return;
    if (!hasActivity) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l.profileUpgradeWallLoginWarningTitle),
            content: Text(l.profileUpgradeWallLoginWarningBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.actionCancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.actionConfirm),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          const Icon(
            Icons.account_circle_outlined,
            size: 72,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            l.profileUpgradeWallHeading,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            l.profileUpgradeWallBody,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.gray),
          ),
          const SizedBox(height: 24),
          _BenefitRow(
            icon: Icons.notifications_active_outlined,
            label: l.profileUpgradeWallBenefitNotifs,
            description: l.profileUpgradeWallBenefitNotifsSub,
          ),
          _BenefitRow(
            icon: Icons.location_searching,
            label: l.profileUpgradeWallBenefitFollow,
            description: l.profileUpgradeWallBenefitFollowSub,
          ),
          _BenefitRow(
            icon: Icons.insights_outlined,
            label: l.profileUpgradeWallBenefitStats,
            description: l.profileUpgradeWallBenefitStatsSub,
          ),
          _BenefitRow(
            icon: Icons.badge_outlined,
            label: l.profileUpgradeWallBenefitProfile,
            description: l.profileUpgradeWallBenefitProfileSub,
          ),
          const SizedBox(height: 24),
          // Hiérarchie inversée (décision 2026-07-25) : « J'ai déjà un
          // compte » en action PRINCIPALE — l'écran de connexion est le hub
          // social 1-tap (Google/Facebook/Apple, création auto du profil).
          // « Créer un compte » (formulaire email, préserve l'historique
          // anonyme via linkWithCredential) passe en action secondaire.
          ElevatedButton(
            onPressed: () => _confirmLoginSwitch(context),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(l.profileUpgradeWallAlreadyAccount),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UpgradeAccountScreen(),
                  ),
                ),
            child: Text(l.profileUpgradeWallCTA),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.label,
    this.description,
  });

  final IconData icon;
  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.gray,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.gray),
      title: Text(
        label,
        style: const TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          color: AppColors.dark,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
