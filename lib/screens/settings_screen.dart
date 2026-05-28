import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/locale_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import 'onboarding_gate.dart';
import 'onboarding_screen.dart';

/// Écran « Paramètres » — point d'entrée unique pour les préférences
/// transversales (notifications pour le moment ; pourra héberger thème,
/// langue, options de confidentialité, etc.).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l.settingsSectionNotifications),
          const _NotificationsToggle(),
          _SectionHeader(l.settingsSectionHelp),
          const _ReplayOnboardingTile(),
          // Sélecteur de langue : utile aux devs / QA pour tester FR↔EN sans
          // changer la langue du téléphone. Caché en build release.
          if (!kReleaseMode) ...[
            _SectionHeader(l.settingsSectionLanguageDebug),
            const _LanguagePickerTile(),
          ],
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

/// Sélecteur de langue debug. Affiche la sélection courante et ouvre un
/// SimpleDialog avec « Système / Français / Anglais ». Persiste via
/// [LocaleProvider] (SharedPreferences).
class _LanguagePickerTile extends StatelessWidget {
  const _LanguagePickerTile();

  String _labelFor(BuildContext context, Locale? locale) {
    final l = AppLocalizations.of(context);
    if (locale == null) return l.languageSystem;
    switch (locale.languageCode) {
      case 'fr':
        return l.languageFrench;
      case 'en':
        return l.languageEnglish;
      default:
        return locale.languageCode;
    }
  }

  Future<void> _pick(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final provider = context.read<LocaleProvider>();
    final selected = await showDialog<Locale?>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: Text(l.settingsLanguageLabel),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l.languageSystem),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(const Locale('fr')),
                child: Text(l.languageFrench),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(const Locale('en')),
                child: Text(l.languageEnglish),
              ),
            ],
          ),
    );
    // `selected == null` est ambigu (dialog dismiss vs choix « Système »).
    // On distingue via le 2e Navigator.pop(null) qui retourne `null`
    // explicitement → ici on l'accepte comme un choix « Système ».
    // Si l'utilisateur tape hors du dialog, on reçoit aussi null → ok, on
    // applique « Système ». Pas critique vu que c'est un outil de debug.
    await provider.setLocale(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = context.watch<LocaleProvider>().locale;
    return ListTile(
      leading: const Icon(Icons.translate, color: AppColors.gray),
      title: Text(l.settingsLanguageLabel),
      subtitle: Text(
        _labelFor(context, current),
        style: const TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pick(context),
    );
  }
}

/// Re-déclenche l'écran d'onboarding (utile après une mise à jour majeure).
/// On affiche l'OnboardingScreen en plein écran ; à la fin (« Commencer » ou
/// « Passer »), on retombe sur l'écran Paramètres.
class _ReplayOnboardingTile extends StatelessWidget {
  const _ReplayOnboardingTile();

  Future<void> _replay(BuildContext context) async {
    // On n'invalide PAS le flag SharedPreferences : la prochaine ouverture de
    // l'app n'affichera donc pas à nouveau l'onboarding pour rien. On se
    // contente d'ouvrir l'écran à la demande.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => OnboardingScreen(
              onDone: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(OnboardingGate.prefKey, true);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.help_outline, color: AppColors.gray),
      title: Text(l.settingsReplayOnboarding),
      subtitle: Text(
        l.settingsReplayOnboardingDescription,
        style: const TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _replay(context),
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
    final l = AppLocalizations.of(context);
    return SwitchListTile(
      secondary: const Icon(
        Icons.notifications_outlined,
        color: AppColors.gray,
      ),
      title: Text(l.settingsReceiveAlerts),
      subtitle: Text(
        l.settingsReceiveAlertsDescription,
        style: const TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      value: _enabled ?? true,
      onChanged: (_enabled == null || _busy) ? null : _toggle,
    );
  }
}
