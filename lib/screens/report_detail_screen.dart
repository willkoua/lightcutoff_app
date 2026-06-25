import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/confirmation.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../providers/auth_provider.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../utils/l10n_helpers.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/njuka_app_bar.dart';

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  /// Flux du report par id : permet d'afficher un report **hors** de la liste
  /// temps réel (ouverture depuis une notification ou l'anti-doublon) et de
  /// suivre ses mises à jour (compteurs) en direct.
  late final Stream<Report?> _reportStream;

  /// Compteur de confirmations **optimiste** : à la confirmation, on affiche
  /// +1 sans attendre le round-trip serveur (le stream réconcilie ensuite).
  int? _optimisticConfirmCount;

  @override
  void initState() {
    super.initState();
    _reportStream = context.read<ReportProvider>().watchReport(widget.reportId);
    // Hydrate l'état « j'ai déjà voté » depuis le serveur (survit à un
    // redémarrage), après le 1er frame pour disposer du provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ReportProvider>().hydrateMyVotes(widget.reportId);
      }
    });
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndArchive(
    BuildContext context,
    ReportProvider provider,
    String reportId,
  ) async {
    final l = AppLocalizations.of(context);
    // Demande la RAISON de la suppression (choix obligatoire).
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteReasonDialog(),
    );
    if (reason == null || !context.mounted) return;

    final ok = await provider.archive(reportId, reason: reason);
    if (!context.mounted) return;
    if (ok) {
      _snack(context, l.reportDetailDeleted);
      // On revient à la liste — l'écran de détail n'a plus de sens.
      Navigator.of(context).pop();
    } else {
      _snack(context, l.reportDetailDeleteFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = context.watch<ReportProvider>();
    return StreamBuilder<Report?>(
      stream: _reportStream,
      builder: (context, snapshot) {
        // Repli : tant que le stream Firestore n'a pas émis, on tente la liste
        // temps réel locale ; sinon on charge le report par son id.
        final report = snapshot.data ?? provider.reportById(widget.reportId);
        if (report == null) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: NjukaAppBar(title: l.reportDetailTitleShort),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: NjukaAppBar(title: l.reportDetailTitleShort),
            body: Center(child: Text(l.reportDetailNotFound)),
          );
        }

        final ongoing = report.status == OutageStatus.ongoing;
        final isAuthor = provider.isAuthor(report);
        final isAdmin =
            context.watch<AuthProvider>().profile?.role == UserRole.admin;
        // Le détail des confirmations n'est lisible que par l'auteur ou un admin.
        final canViewTimeline = isAuthor || isAdmin;
        // Compteur affiché = max(serveur, optimiste) → ne descend jamais et
        // bouge immédiatement quand l'utilisateur confirme.
        final confirmCount =
            (_optimisticConfirmCount != null &&
                    _optimisticConfirmCount! > report.confirmationCount)
                ? _optimisticConfirmCount!
                : report.confirmationCount;

        return Scaffold(
          appBar: NjukaAppBar(title: l.reportDetailTitle),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _StatusChip(
                ongoing: ongoing,
                label: outageStatusLabel(context, report.status),
              ),
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.place_outlined,
                text:
                    report.location.label.isEmpty
                        ? l.reportDetailZoneUnknown
                        : report.location.label,
                bold: true,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.bolt_outlined,
                text: outageTypeLabel(context, report.type),
              ),
              if (report.authorUsername != null &&
                  report.authorUsername!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.person_outline,
                  text: '@${report.authorUsername}',
                ),
              ],
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.schedule,
                text: l.reportDetailReportedAt(
                  relativeTimeL10n(context, report.reportedAt),
                ),
              ),
              if (!ongoing && report.resolvedAt != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.check_circle_outline,
                  text: l.reportDetailResolvedAt(
                    relativeTimeL10n(context, report.resolvedAt),
                  ),
                ),
              ],
              if (report.description != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Text(report.description!),
                ),
              ],
              if (report.mediaUrl != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    report.mediaUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Coupures « en cours » :
              //   - les tiers peuvent confirmer (« c'est coupé chez moi aussi »)
              //   - tout le monde (auteur compris) peut déclarer le retour du courant
              //     → l'auto-résolution est portée par une Cloud Function quand
              //     le seuil de rétablissements est franchi.
              if (ongoing) ...[
                if (!isAuthor)
                  if (provider.iConfirmed(report.id))
                    const _VotedBanner(labelKey: _Vote.confirmed)
                  else
                    ElevatedButton.icon(
                      onPressed: () async {
                        final go = await showConfirmDialog(
                          context,
                          title: l.confirmOutageTitle,
                          message: l.confirmOutageBody,
                          confirmLabel: l.actionConfirm,
                        );
                        if (!go || !context.mounted) return;
                        final ok = await provider.confirm(report.id);
                        if (ok && mounted) {
                          // Feedback immédiat : +1 sans attendre le serveur.
                          setState(
                            () =>
                                _optimisticConfirmCount =
                                    report.confirmationCount + 1,
                          );
                        }
                        if (context.mounted) {
                          _snack(
                            context,
                            ok
                                ? l.reportDetailSnackConfirmed
                                : l.reportDetailSnackConfirmFailed,
                          );
                        }
                      },
                      icon: const Icon(Icons.thumb_up_outlined),
                      label: Text(l.reportDetailConfirmButton),
                    ),
                if (!isAuthor) const SizedBox(height: 8),
                if (provider.iRestored(report.id))
                  const _VotedBanner(labelKey: _Vote.restored)
                else
                  OutlinedButton.icon(
                    onPressed: () async {
                      final go = await showConfirmDialog(
                        context,
                        title: l.confirmRestoreTitle,
                        message: l.confirmRestoreBody,
                        confirmLabel: l.confirmRestoreAction,
                      );
                      if (!go || !context.mounted) return;
                      final ok = await provider.markRestored(report.id);
                      if (context.mounted) {
                        _snack(
                          context,
                          ok
                              ? l.reportDetailSnackRestoredOk
                              : l.reportDetailSnackRestoredFailed,
                        );
                      }
                    },
                    icon: const Icon(Icons.lightbulb_outline),
                    label: Text(l.reportDetailMarkRestoredButton),
                  ),
              ],
              // Compteur public de rétablissements (sans détails individuels).
              if (report.restorationCount > 0) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.lightbulb,
                      size: 18,
                      color: AppColors.resolved,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.reportDetailRestorationCount(report.restorationCount),
                        style: const TextStyle(
                          color: AppColors.gray,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Action destructive de l'auteur : soft-delete. Disponible quel que
              // soit le status (l'auteur peut retirer un report même rétabli ou
              // déjà confirmé). La suppression définitive arrive automatiquement
              // après 30 jours via le cron `purgeArchivedReports`.
              if (isAuthor) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed:
                      () => _confirmAndArchive(context, provider, report.id),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.orange,
                  ),
                  label: Text(
                    l.reportDetailDeleteButton,
                    style: const TextStyle(color: AppColors.orange),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.orange),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                l.reportDetailConfirmationsSection,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (canViewTimeline)
                _ConfirmationTimeline(
                  reportId: widget.reportId,
                  currentUid: provider.currentUid,
                  stream: provider.watchConfirmations(widget.reportId),
                )
              else
                _CountOnly(count: confirmCount),
            ],
          ),
        );
      },
    );
  }
}

/// Vue anonyme : seul le compteur, sans détail des confirmants.
class _CountOnly extends StatelessWidget {
  const _CountOnly({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.how_to_reg, size: 22, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              l.reportDetailConfirmationsCount(count),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l.reportDetailConfirmationsPrivate,
          style: const TextStyle(color: AppColors.gray, fontSize: 13),
        ),
      ],
    );
  }
}

class _ConfirmationTimeline extends StatelessWidget {
  const _ConfirmationTimeline({
    required this.reportId,
    required this.currentUid,
    required this.stream,
  });

  final String reportId;
  final String? currentUid;
  final Stream<List<Confirmation>> stream;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return StreamBuilder<List<Confirmation>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final confirmations = snapshot.data ?? [];
        if (confirmations.isEmpty) {
          return Text(
            l.reportDetailNoConfirmations,
            style: const TextStyle(color: AppColors.gray),
          );
        }

        final now = DateTime.now();
        final recent =
            confirmations
                .where(
                  (c) =>
                      c.createdAt != null &&
                      now.difference(c.createdAt!) < const Duration(hours: 1),
                )
                .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatPill(
                  value: '${confirmations.length}',
                  label: l.reportDetailStatPillTotal,
                ),
                const SizedBox(width: 12),
                _StatPill(
                  value: '$recent',
                  label: l.reportDetailStatPillRecent,
                  highlight: recent > 0,
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final c in confirmations)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.how_to_reg,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.userId == currentUid
                            ? l.reportDetailConfirmedByYou
                            : l.reportDetailConfirmedByOther,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      relativeTimeL10n(context, c.createdAt),
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.primary : AppColors.gray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.gray)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.bold = false});

  final IconData icon;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.gray),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog de suppression : oblige à choisir une **raison** avant de confirmer.
/// Renvoie le code de la raison (`error`/`duplicate`/`resolved`/`other`) ou
/// `null` si annulé.
class _DeleteReasonDialog extends StatefulWidget {
  const _DeleteReasonDialog();

  @override
  State<_DeleteReasonDialog> createState() => _DeleteReasonDialogState();
}

class _DeleteReasonDialogState extends State<_DeleteReasonDialog> {
  String? _reason;
  final _otherText = TextEditingController();

  @override
  void dispose() {
    _otherText.dispose();
    super.dispose();
  }

  /// Valeur renvoyée : le code ; si « autre » + texte saisi, on y accole la
  /// précision libre (« other: … »).
  String get _result {
    if (_reason == 'other') {
      final extra = _otherText.text.trim();
      return extra.isEmpty ? 'other' : 'other: $extra';
    }
    return _reason!;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final options = <String, String>{
      'error': l.deleteReasonError,
      'duplicate': l.deleteReasonDuplicate,
      'resolved': l.deleteReasonResolved,
      'other': l.deleteReasonOther,
    };
    return AlertDialog(
      title: Text(l.reportDetailDeleteDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.deleteReasonPrompt,
              style: const TextStyle(color: AppColors.gray, fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final e in options.entries)
              RadioListTile<String>(
                value: e.key,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                title: Text(e.value),
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: AppColors.orange,
              ),
            // Champ libre facultatif quand « Autre » est sélectionné.
            if (_reason == 'other')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextField(
                  controller: _otherText,
                  autofocus: true,
                  maxLength: 200,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: l.deleteReasonOtherHint,
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionCancel),
        ),
        ElevatedButton(
          // Désactivé tant qu'aucune raison n'est choisie (le texte « autre »
          // reste facultatif).
          onPressed:
              _reason == null ? null : () => Navigator.of(context).pop(_result),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: AppColors.white,
          ),
          child: Text(l.actionDelete),
        ),
      ],
    );
  }
}

enum _Vote { confirmed, restored }

/// Bandeau passif (pleine largeur) confirmant que l'utilisateur a déjà voté —
/// remplace le bouton d'action correspondant pour un retour visuel clair.
class _VotedBanner extends StatelessWidget {
  const _VotedBanner({required this.labelKey});

  final _Vote labelKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label =
        labelKey == _Vote.confirmed
            ? l.reportVoteConfirmedByYou
            : l.reportVoteRestoredByYou;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.resolved.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.resolved.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 20, color: AppColors.resolved),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.resolved,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.ongoing, required this.label});

  final bool ongoing;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ongoing ? AppColors.ongoing : AppColors.resolved;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
