import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon profil'),
        actions: [
          if (profile != null)
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EditProfileScreen(),
                ),
              ),
            ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                _Avatar(name: profile.displayName),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    profile.displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
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
                  icon: Icons.phone_outlined,
                  label: 'Téléphone',
                  value: profile.phoneNumber?.isNotEmpty == true
                      ? profile.phoneNumber!
                      : 'Non renseigné',
                ),
                _InfoTile(
                  icon: Icons.place_outlined,
                  label: 'Résidence',
                  value: profile.homeLocation.label.isEmpty
                      ? 'Non renseignée'
                      : profile.homeLocation.label,
                ),
                _InfoTile(
                  icon: Icons.badge_outlined,
                  label: 'Rôle',
                  value: profile.role.label,
                ),
                _InfoTile(
                  icon: Icons.event_outlined,
                  label: 'Membre depuis',
                  value: profile.createdAt != null
                      ? relativeTime(profile.createdAt)
                      : '—',
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => context.read<AuthProvider>().logout(),
                  icon: const Icon(Icons.logout, color: AppColors.orange),
                  label: const Text(
                    'Se déconnecter',
                    style: TextStyle(color: AppColors.orange),
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
    final initials = name.trim().isEmpty
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
      title: Text(label, style: const TextStyle(color: AppColors.gray, fontSize: 13)),
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
