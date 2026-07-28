import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/app_constants.dart';
import '../config/utilities.dart';
import '../models/app_error.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/region_provider.dart';
import '../providers/report_provider.dart';
import '../repositories/location_repository.dart';
import '../theme/app_colors.dart';
import 'report_detail_screen.dart';
import '../utils/l10n_helpers.dart';
import '../utils/media.dart';
import '../widgets/anonymous_first_report_sheet.dart';
import '../widgets/location_permission_sheet.dart';
import '../widgets/service_visuals.dart';

enum _DupChoice { confirm, anyway, viewMine, cancel }

/// Choix offert quand le GPS est indisponible : autoriser la localisation, ou
/// décrire sa position manuellement.
enum _LocFallback { allow, describe }

/// Ouvre le formulaire de signalement en **bottom sheet modal** (mêmes deux
/// points d'entrée : FAB de la Liste et de la Carte). Ré-injecte le
/// [ReportProvider] pour que la modale partage le même état.
Future<void> showReportFormSheet(
  BuildContext context,
  ReportProvider provider,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // grandit avec le contenu + le clavier
    showDragHandle: true,
    builder:
        (_) => ChangeNotifierProvider<ReportProvider>.value(
          value: provider,
          child: const ReportFormScreen(),
        ),
  );
}

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _description = TextEditingController();
  final _picker = ImagePicker();
  String? _mediaUrl;
  bool _uploadingMedia = false;

  /// Attestation anti-faux signalement (inspirée de coupure.ci) : **obligatoire**
  /// pour activer l'envoi → réduit le bruit (disjoncteur/compteur perso).
  bool _attested = false;

  /// Date/heure de **constatation** (facultatif). Si non renseignées, le report
  /// est horodaté « maintenant » (serveur).
  DateTime? _observedDate;
  TimeOfDay? _observedTime;

  /// Service du signalement. Initialisé en `initState` à partir du filtre actif
  /// du `RegionProvider` (si l'utilisateur consulte Eau, on présume qu'il
  /// veut signaler une coupure d'eau) ; défaut `electricity` sinon.
  ServiceType? _serviceType;

  @override
  void initState() {
    super.initState();
    final region = context.read<RegionProvider>();
    _serviceType = region.serviceFilter ?? ServiceType.electricity;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    // L'upload Storage ne se met pas en file hors ligne → on bloque proprement.
    if (context.read<ConnectivityProvider>().isOffline) {
      _snack(AppLocalizations.of(context).reportFormMediaOffline);
      return;
    }
    final provider = context.read<ReportProvider>();
    final file = await _picker.pickMedia();
    if (file == null || !mounted) return;
    setState(() => _uploadingMedia = true);
    final bytes = await file.readAsBytes();
    final outcome = await prepareMedia(
      bytes,
      filename: file.name,
      mimeType: file.mimeType,
    );
    if (!mounted) return;
    if (outcome.error != null) {
      setState(() => _uploadingMedia = false);
      _snack(_mediaErrorMessage(context, outcome.error!));
      return;
    }
    final media = outcome.media!;
    final url = await provider.uploadDescriptionMedia(
      media.bytes,
      contentType: media.contentType,
    );
    if (!mounted) return;
    setState(() {
      _uploadingMedia = false;
      _mediaUrl = url;
    });
    if (url == null) {
      _snack(AppLocalizations.of(context).reportFormMediaAddFailed);
    }
  }

  String _mediaErrorMessage(BuildContext context, MediaError error) {
    final l = AppLocalizations.of(context);
    return switch (error) {
      MediaError.unsupportedType => l.reportFormMediaUnsupported,
      MediaError.tooLarge => l.reportFormMediaTooLarge,
      MediaError.invalidImage => l.reportFormMediaInvalidImage,
    };
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Combine date + heure de constatation en un [DateTime], ou `null` si aucune
  /// n'est saisie (→ horodatage « maintenant »). Jamais dans le futur.
  DateTime? _observedAt() {
    if (_observedDate == null && _observedTime == null) return null;
    final now = DateTime.now();
    final d = _observedDate ?? now;
    final t = _observedTime ?? TimeOfDay.fromDateTime(now);
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    return dt.isAfter(now) ? now : dt;
  }

  String _formatObservedDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickObservedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _observedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked != null) setState(() => _observedDate = picked);
  }

  Future<void> _pickObservedTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _observedTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _observedTime = picked);
  }

  void _finish(String message, {required bool success}) {
    if (success) {
      // Capture le navigator parent AVANT de pop la modale : son `context`
      // reste valide après pop (le navigator est plus haut dans l'arbre que
      // la bottom-sheet du formulaire) — sert à afficher le hint anonyme.
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      _snack(message);
      // Best-effort, non bloquant : si l'utilisateur est anonyme et que le
      // flag n'est pas posé, montre la bottom-sheet « Garde tes signalements »
      // (une seule fois par appareil). Géré dans le helper, no-op sinon.
      unawaited(showAnonymousFirstReportHintIfNeeded(rootContext));
    } else {
      _snack(message);
    }
  }

  /// Bandeau affiché quand un pays est sélectionné dans les Paramètres
  /// (dev/staging uniquement) et qu'il diffère du pays détecté : informe que
  /// le signalement sera rattaché au pays sélectionné, pas au pays réel.
  List<Widget> _countryOverrideBanner(
    BuildContext context,
    AppLocalizations l,
  ) {
    final region = context.watch<RegionProvider>();
    final selected = region.userCountry;
    final detected = region.detectedCountry;
    if (selected == null || detected == null || selected == detected) {
      return const [];
    }
    final selectedLabel = countryLabelForIso(selected) ?? selected;
    final detectedLabel = countryLabelForIso(detected) ?? detected;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.public, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.reportFormCountryOverrideInfo(selectedLabel, detectedLabel),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _submit() async {
    final provider = context.read<ReportProvider>();
    final access = await provider.checkLocationAccess();
    if (!mounted) return;
    if (access == LocationAccess.granted) {
      await _proceedWithGps(provider);
      return;
    }
    // GPS indisponible : on ne bloque plus le signalement — on propose
    // d'autoriser la localisation OU de décrire sa position manuellement.
    final choice = await _showLocationFallback(access);
    if (!mounted || choice == null) return;
    switch (choice) {
      case _LocFallback.allow:
        switch (access) {
          case LocationAccess.deniedForever:
          case LocationAccess.serviceDisabled:
            await provider.openLocationSettings();
          case LocationAccess.denied:
            final accept = await _showLocationPriming();
            if (mounted && accept) await _proceedWithGps(provider);
          case LocationAccess.granted:
            break;
        }
      case _LocFallback.describe:
        await _describeAndProceed(provider);
    }
  }

  Future<bool> _showLocationPriming() => showLocationPermissionSheet(context);

  /// Dialogue affiché quand la position GPS n'est pas disponible : laisse le
  /// choix entre (ré)autoriser la localisation et décrire sa position.
  Future<_LocFallback?> _showLocationFallback(LocationAccess access) {
    final l = AppLocalizations.of(context);
    final needsSettings =
        access == LocationAccess.deniedForever ||
        access == LocationAccess.serviceDisabled;
    return showDialog<_LocFallback>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l.reportFormLocationUnavailableTitle),
            content: Text(l.reportFormLocationUnavailableBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(_LocFallback.describe),
                child: Text(l.reportFormDescribePositionAction),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(_LocFallback.allow),
                child: Text(
                  needsSettings
                      ? l.actionOpenSettings
                      : l.reportFormAllowLocation,
                ),
              ),
            ],
          ),
    );
  }

  /// Saisie d'une position décrite (quartier / ville / adresse). Renvoie la
  /// chaîne saisie, ou `null` si annulé.
  Future<String?> _showDescribePosition() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l.reportFormDescribePositionTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.reportFormDescribePositionBody),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.reportFormDescribePositionHint,
                    prefixIcon: const Icon(Icons.place_outlined),
                  ),
                  onSubmitted: (v) => Navigator.of(ctx).pop(v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.actionCancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text),
                child: Text(l.reportFormDescribePositionConfirm),
              ),
            ],
          ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _proceedWithGps(ReportProvider provider) async {
    final outcome = await provider.prepareReport(
      serviceType: _serviceType ?? ServiceType.electricity,
    );
    if (!mounted) return;
    await _continueWithOutcome(provider, outcome);
  }

  Future<void> _describeAndProceed(ReportProvider provider) async {
    final l = AppLocalizations.of(context);
    final query = await _showDescribePosition();
    if (!mounted || query == null || query.trim().isEmpty) return;
    final outcome = await provider.prepareReportFromDescription(
      query,
      serviceType: _serviceType ?? ServiceType.electricity,
    );
    if (!mounted) return;
    // Message dédié si la description ne correspond à aucun lieu.
    if (outcome.error == AppError.locationNotFound) {
      _snack(l.reportFormAddressNotFound);
      return;
    }
    await _continueWithOutcome(provider, outcome);
  }

  Future<void> _continueWithOutcome(
    ReportProvider provider,
    PrepareOutcome outcome,
  ) async {
    final l = AppLocalizations.of(context);
    final authorUsername = context.read<AuthProvider>().profile?.username;
    if (outcome.error != null) {
      _snack(appErrorLabel(context, outcome.error!));
      return;
    }
    final draft = outcome.draft!;
    final nearby = outcome.nearby;

    if (nearby != null) {
      // Si la coupure existante est la sienne, on bloque la création d'un
      // doublon (« 1 report ongoing par user par zone ») : on propose
      // seulement de la consulter ou d'annuler.
      final isOwn = provider.isAuthor(nearby);
      final choice = await _askDuplicate(nearby, isOwn: isOwn);
      if (!mounted || choice == _DupChoice.cancel) return;
      if (choice == _DupChoice.viewMine) {
        // Ferme le formulaire et ouvre le détail de la coupure existante.
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReportDetailScreen(reportId: nearby.id),
          ),
        );
        return;
      }
      if (choice == _DupChoice.confirm) {
        final ok = await provider.confirm(nearby.id);
        if (!mounted) return;
        _finish(
          ok ? l.reportFormConfirmedSuccess : l.reportDetailSnackConfirmFailed,
          success: ok,
        );
        return;
      }
      // _DupChoice.anyway : on crée un nouveau signalement (cas tiers
      // uniquement — pas proposé si isOwn).
    }

    final error = await provider.createFromDraft(
      draft,
      description: _description.text,
      mediaUrl: _mediaUrl,
      authorUsername: authorUsername,
      serviceType: _serviceType ?? ServiceType.electricity,
      reportedAt: _observedAt(),
      // Pays sélectionné (dev/staging, null en prod) : le signalement est
      // rattaché à ce pays — cohérent avec la liste consultée (bandeau
      // d'information affiché dans le formulaire en cas de décalage).
      countryOverrideIso: context.read<RegionProvider>().userCountry,
    );
    if (!mounted) return;
    _finish(
      error != null
          ? appErrorLabel(context, error)
          : l.reportFormCreatedSuccess,
      success: error == null,
    );
  }

  Future<_DupChoice?> _askDuplicate(Report nearby, {required bool isOwn}) {
    final l = AppLocalizations.of(context);
    final zone =
        nearby.location.label.isEmpty
            ? l.duplicateZoneFallback
            : nearby.location.label;
    final time = relativeTimeL10n(context, nearby.reportedAt);
    final body =
        isOwn
            ? l.duplicateOwnBody(zone, time, nearby.confirmationCount)
            : l.duplicateOtherBody(zone, time, nearby.confirmationCount);
    return showDialog<_DupChoice>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(isOwn ? l.duplicateOwnTitle : l.duplicateOtherTitle),
            content: Text(body),
            actions:
                isOwn
                    ? [
                      TextButton(
                        onPressed:
                            () => Navigator.of(ctx).pop(_DupChoice.cancel),
                        child: Text(l.actionCancel),
                      ),
                      ElevatedButton(
                        onPressed:
                            () => Navigator.of(ctx).pop(_DupChoice.viewMine),
                        child: Text(l.duplicateViewMine),
                      ),
                    ]
                    : [
                      TextButton(
                        onPressed:
                            () => Navigator.of(ctx).pop(_DupChoice.cancel),
                        child: Text(l.actionCancel),
                      ),
                      TextButton(
                        onPressed:
                            () => Navigator.of(ctx).pop(_DupChoice.anyway),
                        child: Text(l.duplicateReportAnyway),
                      ),
                      ElevatedButton(
                        onPressed:
                            () => Navigator.of(ctx).pop(_DupChoice.confirm),
                        child: Text(l.actionConfirm),
                      ),
                    ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submitting = context.watch<ReportProvider>().submitting;
    final l = AppLocalizations.of(context);
    return Padding(
      // Le clavier (viewInsets) pousse le contenu de la modale au-dessus de lui.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.reportFormTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Bandeau d'information (dev/staging) : un pays est sélectionné
              // dans les Paramètres et il diffère du pays détecté → le
              // signalement sera rattaché au pays SÉLECTIONNÉ (2026-07-28).
              ..._countryOverrideBanner(context, l),
              // Date/heure de constatation (facultatif) — placée en TÊTE du
              // formulaire ; défaut « maintenant » si non renseignée.
              Text(
                l.reportFormObservedAtLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickObservedDate,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(
                        _observedDate == null
                            ? l.reportFormObservedDate
                            : _formatObservedDate(_observedDate!),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickObservedTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        _observedTime == null
                            ? l.reportFormObservedTime
                            : _observedTime!.format(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_observedDate != null || _observedTime != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      color: AppColors.gray,
                      onPressed:
                          () => setState(() {
                            _observedDate = null;
                            _observedTime = null;
                          }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              // Sélecteur de service (multi-service, pivot étape 3).
              Text(
                l.reportFormServiceLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<ServiceType>(
                segments: [
                  ButtonSegment(
                    value: ServiceType.electricity,
                    label: Text(
                      serviceTypeLabel(context, ServiceType.electricity),
                    ),
                    icon: Icon(serviceTypeIcon(ServiceType.electricity)),
                  ),
                  ButtonSegment(
                    value: ServiceType.water,
                    label: Text(serviceTypeLabel(context, ServiceType.water)),
                    icon: Icon(serviceTypeIcon(ServiceType.water)),
                  ),
                ],
                selected: {_serviceType ?? ServiceType.electricity},
                onSelectionChanged:
                    (set) => setState(() => _serviceType = set.first),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.my_location,
                    size: 18,
                    color: AppColors.gray,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.reportFormPositionHint,
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                l.reportFormDescriptionLabel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                maxLines: 3,
                maxLength: AppConstants.maxDescriptionLength,
                decoration: InputDecoration(
                  hintText: l.reportFormDescriptionHint,
                ),
              ),
              const SizedBox(height: 8),
              _MediaField(
                mediaUrl: _mediaUrl,
                uploading: _uploadingMedia,
                onPick: _pickMedia,
                onRemove: () => setState(() => _mediaUrl = null),
              ),
              const SizedBox(height: 16),
              // Attestation anti-faux signalement (obligatoire pour envoyer).
              InkWell(
                onTap: () => setState(() => _attested = !_attested),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _attested,
                      onChanged: (v) => setState(() => _attested = v ?? false),
                    ),
                    Expanded(
                      child: Text(
                        l.reportFormAttestation,
                        style: const TextStyle(
                          color: AppColors.gray,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: (submitting || !_attested) ? null : _submit,
                icon:
                    submitting
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.dark,
                          ),
                        )
                        : const Icon(Icons.send),
                label: Text(
                  submitting ? l.reportFormSubmitting : l.actionSignal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Champ d'ajout d'un média (image ou GIF, depuis l'appareil) à la description.
class _MediaField extends StatelessWidget {
  const _MediaField({
    required this.mediaUrl,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  final String? mediaUrl;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (uploading) {
      return Row(
        children: [
          const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            l.reportFormMediaUploading,
            style: const TextStyle(color: AppColors.gray),
          ),
        ],
      );
    }
    if (mediaUrl == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(l.reportFormAddMedia),
        ),
      );
    }
    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            mediaUrl!,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) => Container(
                  height: 180,
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: CircleAvatar(
            backgroundColor: Colors.black54,
            radius: 16,
            child: IconButton(
              iconSize: 18,
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onRemove,
            ),
          ),
        ),
      ],
    );
  }
}
