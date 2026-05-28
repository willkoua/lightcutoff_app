import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';
import '../utils/l10n_helpers.dart';
import 'account_security_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.profileTitle),
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
          IconButton(
            tooltip: l.profileTooltipSettings,
            icon: const Icon(Icons.settings_outlined),
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
          ),
        ],
      ),
      body:
          profile == null
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
                    icon: Icons.badge_outlined,
                    label: l.profileRole,
                    value: userRoleLabel(context, profile.role),
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
