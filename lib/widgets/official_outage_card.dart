import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../config/utilities.dart';
import '../models/official_outage.dart';
import '../providers/auth_provider.dart';
import '../screens/outage_location_map_screen.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../utils/outage_geocode.dart';
import '../utils/share_official_outage.dart';
import 'confirm_dialog.dart';
import 'service_visuals.dart';

/// Cache de géocodage partagé entre les cartes pour la durée de la session
/// (évite de re-géocoder les mêmes quartiers/rues à chaque ouverture de carte).
final Map<String, LatLng?> _outageGeocodeCache = {};

/// Carte d'une coupure **officielle planifiée**. Style bleu « planifié », visuellement
/// distinct des `ReportCard` (ambre) des signalements communautaires.
class OfficialOutageCard extends StatelessWidget {
  const OfficialOutageCard({super.key, required this.outage});

  final OfficialOutage outage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    String dateLabel = outage.progDate;
    try {
      dateLabel = DateFormat.yMMMMEEEEd(
        locale,
      ).format(DateTime.parse(outage.progDate));
    } catch (_) {
      // progDate inattendu : on garde la chaîne brute.
    }
    final window = [
      outage.startTime,
      outage.endTime,
    ].where((s) => s.isNotEmpty).join(' – ');
    final place = [
      outage.ville,
      outage.region,
    ].where((s) => s.isNotEmpty).join(' · ');
    // Libellé de l'opérateur dérivé du provider de la coupure (SOCADEL, Kenya
    // Power, …) — jamais codé en dur. Repli sur l'id en capitales si le registre
    // (remote) n'est pas encore chargé.
    final operator =
        utilityLabelForProvider(outage.provider) ??
        outage.provider.toUpperCase();
    // Couleur du badge alignée sur le service de l'app (ambre élec, sky eau),
    // pour que le tag d'une coupure d'électricité ait la couleur « électricité ».
    final badgeColor = serviceTypeColor(outage.serviceType);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge « Travaux planifiés · <opérateur> » (SOCADEL, Kenya Power…).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.engineering_outlined,
                    size: 14,
                    color: badgeColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l.officialOutagesPlannedBadge(operator),
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Quartier.
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.gray,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    outage.quartier,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            if (place.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  place,
                  style: const TextStyle(color: AppColors.gray, fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            // Date + créneau horaire.
            Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  size: 16,
                  color: AppColors.gray,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    window.isEmpty ? dateLabel : '$dateLabel · $window',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (outage.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                outage.reason,
                style: const TextStyle(color: AppColors.gray, fontSize: 13),
              ),
            ],
            const SizedBox(height: 2),
            // Actions alignées à droite (suivre — compte only — puis calendrier
            // et partage, disponibles pour tous les pays : CM/SOCADEL, KE/KPLC…).
            Row(
              children: [
                const Spacer(),
                _FollowButton(outageKey: outage.followKey),
                IconButton(
                  icon: const Icon(Icons.map_outlined, size: 20),
                  color: AppColors.planned,
                  tooltip: l.officialOutageViewOnMap,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openMap(context),
                ),
                IconButton(
                  icon: const Icon(Icons.event_available_outlined, size: 20),
                  color: AppColors.planned,
                  tooltip: l.officialOutageAddToCalendar,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => addOutageToCalendar(context, outage),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 20),
                  color: AppColors.planned,
                  tooltip: l.reportShareAction,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => shareOfficialOutage(context, outage),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Géocode le quartier (géocodeur natif, sans clé) puis ouvre la carte
  /// centrée dessus avec un marqueur + un cercle approximatif. Snackbar si le
  /// lieu est introuvable.
  Future<void> _openMap(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final country = countryLabelForIso(outage.country) ?? '';

    messenger.showSnackBar(
      SnackBar(
        content: Text(l.officialOutageLocating),
        duration: const Duration(seconds: 6),
      ),
    );
    try {
      final zone = await geocodeOutageZone(
        quartier: outage.quartier,
        ville: outage.ville,
        countryLabel: country,
        reason: outage.reason,
        repo: LocationService(),
        cache: _outageGeocodeCache,
      );
      messenger.hideCurrentSnackBar();
      if (zone == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.officialOutageLocationNotFound)),
        );
        return;
      }
      navigator.push(
        MaterialPageRoute(
          builder:
              (_) => OutageLocationMapScreen(
                point: zone.center,
                title: outage.quartier,
                serviceType: outage.serviceType,
                approxRadiusM: zone.radiusM,
                streetPoints: zone.points,
              ),
        ),
      );
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l.officialOutageLocationNotFound)),
      );
    }
  }
}

/// Bouton « Suivre ce quartier » → alerte avant les coupures planifiées.
class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.outageKey});

  final String outageKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // En session anonyme : `users/{uid}` n'existe pas (règle `!isAnonymous()`),
    // donc `toggleFollowQuartier` taperait dans le mur Firestore. On masque le
    // bouton — l'utilisateur passe par le mur d'upgrade du Profil pour
    // débloquer les notifs et le suivi de quartier.
    final isAnonymous = context.select<AuthProvider, bool>(
      (a) => a.isAnonymous,
    );
    if (isAnonymous) return const SizedBox.shrink();
    final following = context.select<AuthProvider, bool>(
      (a) => a.isFollowingQuartier(outageKey),
    );
    final color = following ? AppColors.planned : AppColors.gray;
    return TextButton.icon(
      onPressed: () async {
        // Confirmation seulement au moment de S'ABONNER (le retrait est direct).
        if (!following) {
          final ok = await showConfirmDialog(
            context,
            title: l.confirmFollowTitle,
            message: l.confirmFollowBody,
            confirmLabel: l.confirmFollowAction,
          );
          if (!ok || !context.mounted) return;
        }
        context.read<AuthProvider>().toggleFollowQuartier(outageKey);
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        following ? Icons.notifications_active : Icons.notifications_none,
        size: 18,
        color: color,
      ),
      label: Text(
        following ? l.officialOutageFollowing : l.officialOutageFollow,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
