import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/app_constants.dart';
import '../models/report.dart';
import '../providers/auth_provider.dart';
import '../providers/report_provider.dart';
import '../repositories/location_repository.dart';
import '../theme/app_colors.dart';
import 'report_detail_screen.dart';
import '../utils/l10n_helpers.dart';
import '../utils/media.dart';
import '../widgets/location_permission_sheet.dart';
import '../widgets/njuka_app_bar.dart';

enum _DupChoice { confirm, anyway, viewMine, cancel }

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

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
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

  void _finish(String message, {required bool success}) {
    if (success) Navigator.of(context).pop();
    _snack(message);
  }

  Future<void> _submit() async {
    final provider = context.read<ReportProvider>();
    final l = AppLocalizations.of(context);
    final access = await provider.checkLocationAccess();
    if (!mounted) return;
    switch (access) {
      case LocationAccess.serviceDisabled:
        _snack(l.reportFormEnableLocation);
        return;
      case LocationAccess.deniedForever:
        await _showSettingsDialog(provider);
        return;
      case LocationAccess.denied:
        final accept = await _showLocationPriming();
        if (!mounted || !accept) return;
      case LocationAccess.granted:
        break;
    }
    await _proceed(provider);
  }

  Future<bool> _showLocationPriming() => showLocationPermissionSheet(context);

  Future<void> _showSettingsDialog(ReportProvider provider) async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l.reportFormLocationDeniedTitle),
            content: Text(l.reportFormLocationDeniedBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.actionCancel),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  provider.openLocationSettings();
                },
                child: Text(l.actionOpenSettings),
              ),
            ],
          ),
    );
  }

  Future<void> _proceed(ReportProvider provider) async {
    final l = AppLocalizations.of(context);
    final authorUsername = context.read<AuthProvider>().profile?.username;
    final outcome = await provider.prepareReport();
    if (!mounted) return;
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
    return Scaffold(
      appBar: NjukaAppBar(title: l.reportFormTitle),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: submitting ? null : _submit,
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
