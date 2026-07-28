import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_constants.dart';
import '../config/utilities.dart';
import '../models/enums.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/region_provider.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../widgets/service_visuals.dart';
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
    final isAnonymous = context.watch<AuthProvider>().isAnonymous;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        children: [
          // Notifs : ciblage par homeLocation/quartiers suivis → N/A en
          // anonyme (pas de profil, le tile est masqué).
          if (!isAnonymous) ...[
            _SectionHeader(l.settingsSectionNotifications),
            const _NotificationsToggle(),
          ],
          // Langue : préférence utilisateur disponible dans TOUS les
          // environnements (y compris prod) — ce n'est plus un outil dev.
          _SectionHeader(l.settingsSectionLanguage),
          const _LanguagePickerTile(),
          _SectionHeader(l.settingsSectionHelp),
          const _ContactSupportTile(),
          const _ReplayOnboardingTile(),
          _SectionHeader(l.settingsSectionLegal),
          const _PrivacyPolicyTile(),
          // Outils dev/QA (pays + pays/compagnie de test) : visibles en dev
          // ET en staging — même en build release. Cachés en prod.
          // Le sélecteur de PAYS a rejoint ce bloc le 2026-07-28 : en prod le
          // pays est détecté automatiquement (GPS puis IP), plus de choix
          // manuel (il cachait leurs propres signalements aux utilisateurs).
          if (AppConfig.showDevTools) ...[
            _SectionHeader(l.settingsSectionRegion),
            const _CountryPickerTile(),
            _SectionHeader(l.settingsSectionProviderDebug),
            const _ProviderPickerTile(service: ServiceType.electricity),
            const _ProviderPickerTile(service: ServiceType.water),
          ],
          // Section admin : visible uniquement si l'utilisateur est admin.
          if (context.watch<AuthProvider>().profile?.role ==
              UserRole.admin) ...[
            _SectionHeader(l.settingsSectionAdmin),
            const _WorldwideToggle(),
          ],
          _SectionHeader(l.settingsSectionAccount),
          // Anonyme : « Effacer cette session » remplace « Supprimer mon
          // compte » (qui n'a pas de sens sans compte). Le reset déclenche
          // signOut puis re-démarre une nouvelle session anonyme via le
          // listener de l'AuthProvider.
          if (isAnonymous)
            const _ResetAnonymousSessionTile()
          else
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
    final label = env == null ? _version! : '$_version · $env';
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

/// Bascule admin : afficher tous les signalements (monde) en levant le
/// cloisonnement par pays. Pilotée par [RegionProvider.worldwide].
class _WorldwideToggle extends StatelessWidget {
  const _WorldwideToggle();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final region = context.watch<RegionProvider>();
    return SwitchListTile(
      secondary: const Icon(Icons.public, color: AppColors.gray),
      title: Text(l.settingsWorldwide),
      subtitle: Text(
        l.settingsWorldwideDescription,
        style: const TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      value: region.worldwide,
      onChanged: (v) => context.read<RegionProvider>().setWorldwide(v),
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

/// « Signaler un problème » : ouvre un brouillon d'email vers
/// [AppConstants.supportEmail] **pré-rempli avec le diagnostic** (version,
/// build, environnement, OS, type de compte, langue) — l'utilisateur n'a que
/// son problème à décrire, et le triage arrive avec tout le contexte.
class _ContactSupportTile extends StatelessWidget {
  const _ContactSupportTile();

  Future<void> _open(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    final theme = Theme.of(context);
    final os = theme.platform == TargetPlatform.iOS ? 'iOS' : 'Android';
    final account =
        auth.isAnonymous
            ? l.supportDiagAnonymous
            : (auth.profile?.username ?? '—');
    final diagnostic = [
      '',
      '',
      '--- ${l.supportDiagSeparator} ---',
      'App : NJUKA ${info.version} (${info.buildNumber})'
          '${AppConfig.envBannerLabel != null ? ' · ${AppConfig.envBannerLabel}' : ''}',
      'OS : $os',
      '${l.supportDiagAccount} : $account',
      '${l.supportDiagLanguage} : ${Localizations.localeOf(context).languageCode}',
    ].join('\n');

    final uri = Uri(
      scheme: 'mailto',
      path: AppConstants.supportEmail,
      query:
          Uri(
            queryParameters: {
              'subject': l.supportEmailSubject(info.version, info.buildNumber),
              'body': l.supportEmailBodyHint + diagnostic,
            },
          ).query,
    );
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      // Pas de client mail configuré : on affiche l'adresse en repli.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l.supportNoMailApp(AppConstants.supportEmail)),
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.support_agent_outlined),
      title: Text(l.supportTileTitle),
      subtitle: Text(
        l.supportTileSubtitle,
        style: const TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _open(context),
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

/// Résultat de la pop du picker de fournisseur. Permet de **distinguer** une
/// fermeture du dialog (tap hors zone → `null` natif de showDialog) d'un
/// choix explicite (« Auto » ou un fournisseur). Sans ce sentinel, on ne
/// peut pas savoir si l'utilisateur a vraiment voulu repasser en Auto ou
/// s'il a dismissé la modale — or l'auto-coupling symétrique de
/// `RegionProvider.setOverride(_, null)` veut connaître l'intention.
class _ProviderChoice {
  const _ProviderChoice._(this.utility, this.isAuto);
  final Utility? utility;
  final bool isAuto;

  static const _ProviderChoice auto = _ProviderChoice._(null, true);
  static _ProviderChoice pick(Utility u) => _ProviderChoice._(u, false);
}

/// Sélecteur de **pays** — outil dev/staging UNIQUEMENT depuis le 2026-07-28
/// (en prod le pays est détecté automatiquement : GPS puis IP).
/// « Automatique » = détection GPS/IP / profil / locale. Choisir un pays
/// explicite le force (prioritaire sur la détection) → utile pour la QA
/// (consulter/seeder un autre pays) ; le formulaire de signalement affiche
/// alors un bandeau si le pays choisi ≠ pays détecté. Persiste via
/// [RegionProvider.setUserCountry].
class _CountryPickerTile extends StatelessWidget {
  const _CountryPickerTile();

  Future<void> _pick(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final region = context.read<RegionProvider>();
    // Valeur retournée : `''` = automatique, sinon un ISO ; `null` = annulé.
    final selected = await showDialog<String>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: Text(l.countryPickerTitle),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(''),
                child: Text(l.countryAuto),
              ),
              for (final c in supportedCountries())
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(c.iso),
                  child: Text(c.label),
                ),
            ],
          ),
    );
    if (selected == null || !context.mounted) return; // dismiss → no-op
    await region.setUserCountry(selected.isEmpty ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final region = context.watch<RegionProvider>();
    final userIso = region.userCountry;
    final subtitle =
        userIso != null
            ? (countryLabelForIso(userIso) ?? userIso)
            : '${l.countryAuto} · ${countryLabelForIso(region.activeCountry) ?? region.activeCountry}';
    return ListTile(
      leading: const Icon(Icons.public, color: AppColors.gray),
      title: Text(l.settingsCountryTile),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.gray, fontSize: 13),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pick(context),
    );
  }
}

/// Sélecteur debug **par service** (un par tuile dans Paramètres) du
/// fournisseur (pays + compagnie). « Auto » = résolution standard
/// (override → GPS → profil → locale → défaut). Sélectionner un fournisseur
/// d'un pays donné **aligne automatiquement l'autre service** sur le pays
/// correspondant si un jumeau existe ; repasser un service en « Auto »
/// bascule **aussi** l'autre en « Auto ». Cf. `RegionProvider.setOverride`.
/// Persiste via [RegionProvider] (2 clés SharedPreferences distinctes).
class _ProviderPickerTile extends StatelessWidget {
  const _ProviderPickerTile({required this.service});

  final ServiceType service;

  Future<void> _pick(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final region = context.read<RegionProvider>();
    final candidates = [
      for (final u in kSupportedUtilities)
        if (u.service == service) u,
    ];
    final choice = await showDialog<_ProviderChoice>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: Text(serviceTypeLabel(context, service)),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(_ProviderChoice.auto),
                child: Text(l.providerAuto),
              ),
              for (final u in candidates)
                SimpleDialogOption(
                  onPressed:
                      () => Navigator.of(ctx).pop(_ProviderChoice.pick(u)),
                  child: Text(u.displayLabel),
                ),
            ],
          ),
    );
    if (choice == null || !context.mounted) return; // dismiss → no-op
    await region.setOverride(service, choice.utility);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final region = context.watch<RegionProvider>();
    final override = region.overrideUtility(service);
    final subtitle =
        override != null
            ? override.displayLabel
            : '${l.providerAuto} · ${region.activeUtility(service)?.displayLabel ?? region.activeCountry}';
    return ListTile(
      leading: Icon(serviceTypeIcon(service), color: AppColors.gray),
      title: Text(serviceTypeLabel(context, service)),
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

/// Tuile « Effacer cette session anonyme » : déconnecte la session anonyme
/// courante. L'`AuthProvider.logout()` réarme le garde-fou interne, donc une
/// nouvelle session anonyme est créée automatiquement par le listener
/// `_onAuthStateChanged`. Les signalements/votes anonymes restent en base
/// (rattachés à l'ancien uid) mais ne sont plus liés à cet appareil.
class _ResetAnonymousSessionTile extends StatelessWidget {
  const _ResetAnonymousSessionTile();

  Future<void> _confirm(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l.settingsResetAnonymousSessionTitle),
            content: Text(l.settingsResetAnonymousSessionBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.actionCancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                ),
                child: Text(l.settingsResetAnonymousSessionConfirm),
              ),
            ],
          ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AuthProvider>().logout();
    if (!context.mounted) return;
    // Retour à la racine : l'AuthGate refera le routing
    // (anonymous → MainShell) une fois la nouvelle session prête.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.refresh, color: AppColors.orange),
      title: Text(
        l.settingsResetAnonymousSession,
        style: const TextStyle(color: AppColors.orange),
      ),
      onTap: () => _confirm(context),
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
