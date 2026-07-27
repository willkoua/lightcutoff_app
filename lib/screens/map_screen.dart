import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../providers/region_provider.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/active_filters_banner.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/njuka_app_bar.dart';
import '../utils/l10n_helpers.dart';
import '../widgets/report_card.dart';
import '../widgets/service_filter_bar.dart';
import '../widgets/service_visuals.dart';
import 'report_form_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _fallbackCenter = LatLng(3.848, 11.502); // Yaoundé
  static const _minZoom = 3.0;
  static const _maxZoom = 18.0;
  // Zoom d'arrivée : niveau quartier, centré sur l'utilisateur.
  static const _arrivalZoom = 15.0;

  final MapController _controller = MapController();
  LatLng? _myPos;
  bool _mapReady = false;
  bool _didInitialCenter = false;

  @override
  void initState() {
    super.initState();
    _loadMyPosition();
  }

  Future<void> _loadMyPosition() async {
    final pos = await context.read<ReportProvider>().myPosition();
    if (!mounted || pos == null) return;
    setState(() => _myPos = LatLng(pos.lat, pos.lng));
    // Si la carte est déjà prête, on centre dès que la position arrive.
    _centerOnMe();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Ouvre un lien d'attribution (échec ignoré : non critique pour la carte).
  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      /* ignore */
    }
  }

  /// Centre la carte sur la position de l'utilisateur (zoom quartier) à
  /// l'arrivée, une seule fois. No-op tant que la carte n'est pas prête ou que
  /// la position n'est pas connue ; ne s'oppose pas aux déplacements manuels
  /// ultérieurs (ne s'exécute qu'au premier centrage).
  void _centerOnMe() {
    if (_didInitialCenter || !_mapReady || _myPos == null) return;
    _didInitialCenter = true;
    _controller.move(_myPos!, _arrivalZoom);
  }

  /// Force le chargement des tuiles de la vue initiale. Sans un premier
  /// évènement caméra, flutter_map peut rester gris jusqu'à ce que l'utilisateur
  /// interagisse — utile quand la position n'est pas (encore) connue et qu'aucun
  /// centrage n'a lieu. Un « move » sur place, après la mise en page, déclenche
  /// le recalcul des tuiles.
  void _primeTiles() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      final cam = _controller.camera;
      _controller.move(cam.center, cam.zoom);
    });
  }

  Future<void> _recenterOnMe() async {
    if (_myPos != null) {
      _controller.move(_myPos!, 15);
      return;
    }
    final pos = await context.read<ReportProvider>().myPosition();
    if (!mounted) return;
    if (pos == null) {
      _snack(AppLocalizations.of(context).snackPositionUnavailable);
      return;
    }
    setState(() => _myPos = LatLng(pos.lat, pos.lng));
    _controller.move(_myPos!, 15);
  }

  /// Ouvre le formulaire de signalement, en ré-injectant le ReportProvider
  /// pour que la nouvelle route ait accès au même état (cf. fix nav depuis
  /// les notifications push).
  void _openReportForm(ReportProvider provider) {
    showReportFormSheet(context, provider);
  }

  void _openDetails(Report report) {
    final provider = context.read<ReportProvider>();
    final l = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => ReportCard(
            report: report,
            isAuthor: provider.isAuthor(report),
            alreadyConfirmed: provider.iConfirmed(report.id),
            alreadyRestored: provider.iRestored(report.id),
            onConfirm: () async {
              final go = await showConfirmDialog(
                context,
                title: l.confirmOutageTitle,
                message: confirmOutageBodyLabel(context, report.serviceType),
                confirmLabel: l.actionConfirm,
              );
              if (!go) return;
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              final ok = await provider.confirm(report.id);
              if (mounted) {
                _snack(
                  ok
                      ? l.reportDetailSnackConfirmed
                      : l.reportDetailSnackConfirmFailed,
                );
              }
            },
            onMarkRestored: () async {
              final go = await showConfirmDialog(
                context,
                title: confirmRestoreTitleLabel(context, report.serviceType),
                message: confirmRestoreBodyLabel(context, report.serviceType),
                confirmLabel: l.confirmRestoreAction,
              );
              if (!go) return;
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              final ok = await provider.markRestored(report.id);
              if (mounted) {
                _snack(
                  ok
                      ? l.reportDetailSnackRestoredOk
                      : l.reportDetailSnackRestoredFailed,
                );
              }
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportProvider>();
    final reports = provider.filteredReports;

    final l = AppLocalizations.of(context);
    final region = context.watch<RegionProvider>();
    // Périmètre actif (pays + proximité) : la proximité restreint l'affichage
    // mais n'est pas dans `hasActiveFilters` → on l'ajoute pour la bannière et
    // l'état vide. Sans ça, sur la carte, le filtre proximité agit en silence.
    final restricted = provider.hasActiveFilters || provider.nearOnly;
    final scope = buildScopeLabel(
      countryLabel:
          region.worldwide
              ? null
              : (region.activeProvider?.countryLabel ?? region.activeCountry),
      nearOnly: provider.nearOnly,
      nearbyLabel: l.filterSheetNearby,
    );
    return Scaffold(
      appBar: NjukaAppBar(title: l.mapTitle, filterProvider: provider),
      // FAB « Signaler » à gauche pour ne pas chevaucher la colonne de
      // boutons zoom/recenter à droite. Réutilise le formulaire commun ; la
      // position du report sera la GPS actuelle de l'utilisateur (cohérent
      // avec le flux depuis la Liste).
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openReportForm(provider),
        icon: const Icon(Icons.add),
        label: Text(l.actionSignal),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _myPos ?? _fallbackCenter,
              initialZoom: 6,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              onMapReady: () {
                _mapReady = true;
                _centerOnMe();
                _primeTiles();
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // Fond de carte : tuiles Stadia Maps si une clé est fournie
              // (--dart-define=STADIA_API_KEY=…), sinon repli OSM brut en dev.
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
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 48,
                  size: const Size(44, 44),
                  padding: const EdgeInsets.all(50),
                  markers: [
                    for (final report in reports)
                      Marker(
                        point: LatLng(report.position.lat, report.position.lng),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => _openDetails(report),
                          // Couleur : statut résolu = vert commun ; en cours =
                          // couleur du service (ambre élec / sky eau).
                          // Icône : on garde le pin (`location_on`) pour la
                          // continuité visuelle, et on superpose une mini icône
                          // service centrée pour différencier d'un coup d'œil.
                          child: _ServiceMarker(
                            color:
                                report.status == OutageStatus.ongoing
                                    ? serviceTypeColor(report.serviceType)
                                    : AppColors.resolved,
                            serviceIcon: serviceTypeIcon(report.serviceType),
                          ),
                        ),
                      ),
                  ],
                  builder:
                      (context, markers) => Container(
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${markers.length}',
                          style: const TextStyle(
                            color: AppColors.dark,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                ),
              ),
              if (_myPos != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _myPos!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
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
              // Attribution obligatoire (licence ODbL d'OpenStreetMap + Stadia).
              // On masque le logo flutter_map (non requis, non cliquable).
              RichAttributionWidget(
                showFlutterMapAttribution: false,
                attributions: [
                  if (AppConfig.useStadiaTiles)
                    TextSourceAttribution(
                      'Stadia Maps',
                      onTap: () => _openUrl('https://stadiamaps.com/'),
                    ),
                  if (AppConfig.useStadiaTiles)
                    TextSourceAttribution(
                      'OpenMapTiles',
                      onTap: () => _openUrl('https://openmaptiles.org/'),
                    ),
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap:
                        () =>
                            _openUrl('https://www.openstreetmap.org/copyright'),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: _recenterOnMe,
              child: const Icon(Icons.my_location),
            ),
          ),
          // Bandeau de tête : bannière « filtres actifs » (si applicable) +
          // sélecteur de service (toujours visible) — empilés sous l'AppBar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  if (restricted && reports.isNotEmpty)
                    ActiveFiltersBanner(
                      count: reports.length,
                      scope: scope,
                      onClear: provider.showAll,
                    ),
                  // Material/élévation pour bien détacher le sélecteur des tuiles
                  // de carte (sinon le SegmentedButton flotte mal sur du fond
                  // texturé).
                  Material(
                    elevation: 2,
                    color: AppColors.white,
                    child: const ServiceFilterBar(),
                  ),
                ],
              ),
            ),
          ),
          // État vide explicite : au lieu d'une carte vide trompeuse, on
          // explique pourquoi rien ne s'affiche et on propose de tout réafficher.
          if (reports.isEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      restricted
                          ? Icons.search_off
                          : Icons.check_circle_outline,
                      color: AppColors.primary,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      restricted
                          ? l.homeEmptyWithFilters
                          : l.homeEmptyAllReports,
                      textAlign: TextAlign.center,
                    ),
                    if (restricted) ...[
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: provider.showAll,
                        child: Text(l.homeClearFilters),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Marqueur cluster d'un report : pin coloré (selon statut/service) avec une
/// mini icône service centrée au-dessus pour identifier d'un coup d'œil élec
/// vs eau.
class _ServiceMarker extends StatelessWidget {
  const _ServiceMarker({required this.color, required this.serviceIcon});

  final Color color;
  final IconData serviceIcon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.location_on, size: 44, color: color),
        // Petit cercle blanc en surimpression avec l'icône service.
        Positioned(
          top: 6,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(serviceIcon, size: 12, color: color),
          ),
        ),
      ],
    );
  }
}
