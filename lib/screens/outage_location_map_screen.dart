import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../utils/outage_geocode.dart';
import '../widgets/service_visuals.dart';

/// Carte d'une **coupure programmée** : marqueur + zone **approximative** (petits
/// buffers autour des rues géocodées) au centre du quartier (on n'a pas les
/// frontières exactes). Permet de **rechercher un lieu** et d'afficher **sa
/// position** (si la géoloc est autorisée). Ouvert depuis le bouton « Voir sur
/// la carte » d'une `OfficialOutageCard`.
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

  /// Rayon approximatif du cercle de repli (mètres).
  final double approxRadiusM;

  /// Rues/repères géocodés de la description (outliers déjà filtrés).
  final List<LatLng> streetPoints;

  @override
  State<OutageLocationMapScreen> createState() =>
      _OutageLocationMapScreenState();
}

class _OutageLocationMapScreenState extends State<OutageLocationMapScreen> {
  final _controller = MapController();
  final _searchCtrl = TextEditingController();
  final _locationService = LocationService();

  LatLng? _myPos; // position de l'utilisateur (si géoloc autorisée)
  LatLng? _searchPos; // dernier lieu recherché

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Centre sur la position de l'utilisateur. `getCurrentLocation` demande la
  /// permission si besoin et ne renvoie rien tant qu'elle n'est pas accordée.
  Future<void> _locateMe() async {
    final l = AppLocalizations.of(context);
    try {
      final res = await _locationService.getCurrentLocation();
      if (!mounted) return;
      final p = LatLng(res.position.lat, res.position.lng);
      setState(() => _myPos = p);
      _controller.move(p, 15);
    } catch (_) {
      if (!mounted) return;
      _snack(l.snackPositionUnavailable);
    }
  }

  /// Géocode la saisie et y recentre la carte (marqueur dédié).
  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    final l = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    try {
      final res = await _locationService.locationFromDescription(q);
      if (!mounted) return;
      final p = LatLng(res.position.lat, res.position.lng);
      setState(() => _searchPos = p);
      _controller.move(p, 15);
    } catch (_) {
      if (!mounted) return;
      _snack(l.officialOutageLocationNotFound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = serviceTypeColor(widget.serviceType);
    final hasStreets = widget.streetPoints.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'outage-locate-me',
        onPressed: _locateMe,
        child: const Icon(Icons.my_location),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.point,
              initialZoom: 14,
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
              // Zone : un petit buffer autour de CHAQUE rue (ils fusionnent là
              // où les rues sont proches). Repli sur un grand cercle si aucune
              // rue n'a pu être géocodée.
              if (hasStreets)
                CircleLayer(
                  circles: [
                    for (final p in widget.streetPoints)
                      CircleMarker(
                        point: p,
                        radius: kOutageStreetBufferM,
                        useRadiusInMeter: true,
                        color: color.withValues(alpha: 0.16),
                        borderColor: color.withValues(alpha: 0.35),
                        borderStrokeWidth: 1,
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
              // Points de rues au centre de chaque buffer.
              CircleLayer(
                circles: [
                  for (final p in widget.streetPoints)
                    CircleMarker(
                      point: p,
                      radius: 4,
                      useRadiusInMeter: false,
                      color: color.withValues(alpha: 0.95),
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Marqueur central du quartier.
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
                  // Lieu recherché.
                  if (_searchPos != null)
                    Marker(
                      point: _searchPos!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.place,
                        color: AppColors.dark,
                        size: 36,
                      ),
                    ),
                  // Ma position.
                  if (_myPos != null)
                    Marker(
                      point: _myPos!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Barre de recherche de lieu.
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _search,
                  ),
                  hintText: l.officialOutageMapSearchHint,
                  filled: true,
                  fillColor: AppColors.white,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          // Bandeau « zone approximative » sous la barre de recherche.
          Positioned(
            top: 64,
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
