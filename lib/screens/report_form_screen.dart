import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../models/report.dart';
import '../providers/report_provider.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatting.dart';

enum _DupChoice { confirm, anyway, cancel }

class ReportFormScreen extends StatefulWidget {
  const ReportFormScreen({super.key});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  OutageCause _cause = OutageCause.unplanned;
  final _description = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
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
    final access = await provider.checkLocationAccess();
    if (!mounted) return;
    switch (access) {
      case LocationAccess.serviceDisabled:
        _snack('Activez la localisation de l\'appareil pour signaler.');
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

  Future<bool> _showLocationPriming() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.my_location, color: AppColors.primary, size: 40),
        title: const Text('Activer la localisation'),
        content: const Text(
          'NJUKA utilise votre position uniquement pour localiser la coupure '
          'que vous signalez. Elle n\'est pas partagée à d\'autres fins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _showSettingsDialog(ReportProvider provider) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Localisation désactivée'),
        content: const Text(
          'La permission de localisation a été refusée. Activez-la dans les '
          'réglages de l\'application pour pouvoir signaler une coupure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              provider.openLocationSettings();
            },
            child: const Text('Ouvrir les réglages'),
          ),
        ],
      ),
    );
  }

  Future<void> _proceed(ReportProvider provider) async {
    final outcome = await provider.prepareReport();
    if (!mounted) return;
    if (outcome.error != null) {
      _snack(outcome.error!);
      return;
    }
    final draft = outcome.draft!;
    final nearby = outcome.nearby;

    if (nearby != null) {
      final choice = await _askDuplicate(nearby);
      if (!mounted || choice == _DupChoice.cancel) return;
      if (choice == _DupChoice.confirm) {
        final ok = await provider.confirm(nearby.id);
        if (!mounted) return;
        _finish(
          ok ? 'Coupure confirmée. Merci !' : 'Échec de la confirmation.',
          success: ok,
        );
        return;
      }
      // _DupChoice.anyway : on crée un nouveau signalement.
    }

    final error = await provider.createFromDraft(
      draft,
      cause: _cause,
      description: _description.text,
    );
    if (!mounted) return;
    _finish(error ?? 'Coupure signalée. Merci !', success: error == null);
  }

  Future<_DupChoice?> _askDuplicate(Report nearby) {
    final zone =
        nearby.location.label.isEmpty ? 'à proximité' : nearby.location.label;
    return showDialog<_DupChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Coupure déjà signalée'),
        content: Text(
          'Une coupure est déjà signalée près d\'ici :\n\n'
          '$zone\n'
          '${relativeTime(nearby.reportedAt)} · '
          '${nearby.confirmationCount} confirmation'
          '${nearby.confirmationCount > 1 ? 's' : ''}\n\n'
          'Voulez-vous la confirmer plutôt que d\'en créer une nouvelle ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DupChoice.cancel),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DupChoice.anyway),
            child: const Text('Signaler quand même'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(_DupChoice.confirm),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submitting = context.watch<ReportProvider>().submitting;
    return Scaffold(
      appBar: AppBar(title: const Text('Signaler une coupure')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.my_location, size: 18, color: AppColors.gray),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Votre position actuelle sera utilisée pour localiser '
                      'la coupure.',
                      style: TextStyle(color: AppColors.gray, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Cause', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<OutageCause>(
                value: _cause,
                items: OutageCause.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.label),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _cause = v ?? _cause),
              ),
              const SizedBox(height: 20),
              const Text('Description (facultatif)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Ex. tout le quartier est touché depuis ce matin.',
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: submitting ? null : _submit,
                icon: submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.dark,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(submitting ? 'Envoi...' : 'Signaler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
