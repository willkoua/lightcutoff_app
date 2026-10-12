import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../utils/outage_geocode.dart';
import '../widgets/service_visuals.dart';

/// Carte d'une **coupure programmée** : marqueur + cercle **approximatif** au
/// centre géocodé du quartier (on n'a pas les frontières exactes de la zone).
/// Écran en lecture seule, ouvert depuis le bouton « Voir sur la carte » d'une
/// `OfficialOutageCard`.
class OutageLocationMapScreen extends StatefulWidget {
  const OutageLocationMapScreen({
    super.key,
    required this.point,
    required this.title,
    required this.serviceType,
    this.approxRadiusM = 1200,
    this.streetPoints = const [],
  });

  /// Centre géocodé du quartier.
  final LatLng point;

  /// Titre (nom du quartier).
  final String title;

  /// Service (couleur du cercle/marqueur : ambre élec, sky eau).
  final ServiceType serviceType;

  /// Rayon approximatif du cercle (mètres) — purement indicatif.
  final double approxRadiusM;

  /// Rues/repères géocodés de la description (outliers déjà filtrés). Affichés
  /// en petits points pour matérialiser la zone réelle quand ils existent.
  final List<LatLng> streetPoints;

  @override
  State<OutageLocationMapScreen> createState() =>
      _OutageLocationMapScreenState();
}

class _OutageLocationMapScreenState extends State<OutageLocationMapScreen> {
  final _controller = MapController();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = serviceTypeColor(widget.serviceType);
    // Polygone (enveloppe) reliant les rues quand on en a ≥ 3 ; sinon cercle.
    final hull = convexHull(widget.streetPoints);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.point,
              initialZoom: 14,
              // Garantit le centrage/zoom une fois la carte prête (initialZoom
              // seul ne suffisait pas sur certains appareils).
              onMapReady: () => _controller.move(widget.point, 14),
            ),
            children: [
              if (AppConfig.useStadiaTiles)
                TileLayer(
                  urlTemplate:
                      'https://tiles.stadiamaps.com/tiles/alidade_smooth/'
                      '{z}/{x}/{y}.png?api_key={apiKey}',
                  additionalOptions: {'apiKey': AppConfig.stadiaApiKey},
                  userAgentPackageName: 'com.njuka.app',
                  maxZoom: 20,
                )
              else
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.njuka.app',
                  maxZoom: 19,
                ),
              // Zone : polygone reliant les rues (≥ 3), sinon cercle englobant.
              if (hull.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: hull,
                      color: color.withValues(alpha: 0.18),
                      borderColor: color.withValues(alpha: 0.7),
                      borderStrokeWidth: 2,
                    ),
                  ],
                )
              else
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: widget.point,
                      radius: widget.approxRadiusM,
                      useRadiusInMeter: true,
                      color: color.withValues(alpha: 0.18),
                      borderColor: color.withValues(alpha: 0.6),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              // Points de rues (taille en pixels, fixe au zoom) — matérialise
              // les rues réellement citées dans la description.
              CircleLayer(
                circles: [
                  for (final p in widget.streetPoints)
                    CircleMarker(
                      point: p,
                      radius: 5,
                      useRadiusInMeter: false,
                      color: color.withValues(alpha: 0.9),
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.point,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        serviceTypeIcon(widget.serviceType),
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Bandeau « zone approximative » — honnêteté : ce n'est pas le contour
          // exact de la coupure, juste le centre du quartier.
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.officialOutageMapApproxZone,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
