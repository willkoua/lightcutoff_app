import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_constants.dart';
import '../config/electricity_providers.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/region_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
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
          _SectionHeader(l.settingsSectionLegal),
          const _PrivacyPolicyTile(),
          // Outils dev/QA (langue, pays/compagnie) : visibles en dev ET en
          // staging — même en build release. Cachés uniquement en prod.
          if (AppConfig.showDevTools) ...[
            _SectionHeader(l.settingsSectionLanguageDebug),
            const _LanguagePickerTile(),
            _SectionHeader(l.settingsSectionProviderDebug),
            const _ProviderPickerTile(),
          ],
          _SectionHeader(l.settingsSectionAccount),
          const _DeleteAccountTile(),
          const _VersionFooter(),
        ],
      ),
    );
  }
}

/// Pied de page discret affichant la version de l'application
/// (« version 1.1.0 (2) »). Lue à l'exécution via package_info_plus, donc
/// toujours synchrone avec le `version:` du pubspec — pas de constante à
/// maintenir. En non-prod, suffixe l'environnement pour lever toute ambiguïté.
class _VersionFooter extends StatefulWidget {
  const _VersionFooter();

  @override
  State<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<_VersionFooter> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = '${info.version} (${info.buildNumber})');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_version == null) return const SizedBox(height: 48);
    final env = AppConfig.envBannerLabel;
    final label =
        env == null ? _version! : '$_version · $env';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Center(
        child: Text(
          l.settingsVersion(label),
          style: const TextStyle(color: AppColors.gray, fontSize: 12),
        ),
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

/// Ouvre la politique de confidentialité hébergée (Firebase Hosting) dans le
/// navigateur. URL centralisée dans [AppConstants.privacyPolicyUrl].
class _PrivacyPolicyTile extends StatelessWidget {
  const _PrivacyPolicyTile();

  Future<void> _open(BuildContext context) async {
    final l = AppLocalizations.of(context);
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(AppConstants.privacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.settingsLinkOpenFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.privacy_tip_outlined),
      title: Text(l.settingsPrivacyPolicy),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _open(context),
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

/// Sélecteur debug du fournisseur d'électricité (pays + compagnie). « Auto »
/// = détection (profil → locale → défaut). Persiste via [RegionProvider].
class _ProviderPickerTile extends StatelessWidget {
  const _ProviderPickerTile();

  Future<void> _pick(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final region = context.read<RegionProvider>();
    final selected = await showDialog<ElectricityProvider?>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: Text(l.settingsSectionProviderDebug),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l.providerAuto),
              ),
              for (final p in kSupportedProviders)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(p),
                  child: Text(p.displayLabel),
                ),
            ],
          ),
    );
    await region.setOverride(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final region = context.watch<RegionProvider>();
    final subtitle =
        region.isOverridden
            ? region.overrideProvider!.displayLabel
            : '${l.providerAuto} · ${region.activeProvider?.displayLabel ?? region.activeCountry}';
    return ListTile(
      leading: const Icon(Icons.bolt_outlined, color: AppColors.gray),
      title: Text(l.settingsSectionProviderDebug),
      subtitle: Text(
        subtitle,
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

/// Tuile destructive « Supprimer mon compte » (RGPD / exigence stores).
class _DeleteAccountTile extends StatelessWidget {
  const _DeleteAccountTile();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(
        Icons.delete_forever_outlined,
        color: AppColors.orange,
      ),
      title: Text(
        l.settingsDeleteAccount,
        style: const TextStyle(color: AppColors.orange),
      ),
      onTap:
          () => showDialog<void>(
            context: context,
            builder: (_) => const _DeleteAccountDialog(),
          ),
    );
  }
}

/// Confirmation de suppression : explication + mot de passe (ré-auth). Au
/// succès, on dépile jusqu'à la racine (l'AuthGate affiche alors l'écran de
/// connexion, le compte étant supprimé).
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final l = AppLocalizations.of(context);
    if (_password.text.isEmpty) {
      setState(() => _error = l.validatorPasswordRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.deleteAccount(currentPassword: _password.text);
    if (!mounted) return;
    if (ok) {
      // Compte supprimé + déconnecté : on retire Paramètres + ce dialog ;
      // l'AuthGate (route racine) bascule sur la connexion.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      setState(() {
        _busy = false;
        _error =
            auth.error != null
                ? appErrorLabel(context, auth.error!)
                : l.errorGeneric;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.deleteAccountBody),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.deleteAccountPasswordLabel,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _confirm,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
          child:
              _busy
                  ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                  : Text(l.deleteAccountConfirm),
        ),
      ],
    );
  }
}
