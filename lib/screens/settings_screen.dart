import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/app_colors.dart';

/// Écran « Paramètres » — point d'entrée unique pour les préférences
/// transversales (notifications pour le moment ; pourra héberger thème,
/// langue, options de confidentialité, etc.).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: const [
          _SectionHeader('Notifications'),
          _NotificationsToggle(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.gray,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NotificationsToggle extends StatefulWidget {
  const _NotificationsToggle();

  @override
  State<_NotificationsToggle> createState() => _NotificationsToggleState();
}

class _NotificationsToggleState extends State<_NotificationsToggle> {
  bool? _enabled; // null = en cours de chargement
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await NotificationService.instance.readFcmEnabled();
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _enabled = value;
      _busy = true;
    });
    await NotificationService.instance.setFcmEnabled(value);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(
        Icons.notifications_outlined,
        color: AppColors.gray,
      ),
      title: const Text('Recevoir les alertes'),
      subtitle: const Text(
        'Notifications de coupures dans votre zone',
        style: TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      value: _enabled ?? true,
      onChanged: (_enabled == null || _busy) ? null : _toggle,
    );
  }
}
