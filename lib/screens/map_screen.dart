import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../models/report.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/njuka_app_bar.dart';
import '../widgets/report_card.dart';
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

  final MapController _controller = MapController();
  LatLng? _myPos;
  bool _mapReady = false;
  bool _didFit = false;

  @override
  void initState() {
    super.initState();
    _loadMyPosition();
  }

  Future<void> _loadMyPosition() async {
    final pos = await context.read<ReportProvider>().myPosition();
    if (!mounted || pos == null) return;
    setState(() => _myPos = LatLng(pos.lat, pos.lng));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Recadre une fois la carte prête et les coupures chargées.
  void _maybeFit(List<LatLng> points) {
    if (!_mapReady || _didFit || points.isEmpty) return;
    _didFit = true;
    if (points.length == 1) {
      _controller.move(points.first, 13);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(60),
        maxZoom: 15,
      ),
    );
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => ChangeNotifierProvider<ReportProvider>.value(
              value: provider,
              child: const ReportFormScreen(),
            ),
      ),
    );
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
            onConfirm: () async {
              Navigator.of(sheetContext).pop();
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
              Navigator.of(sheetContext).pop();
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
    final points =
        reports.map((r) => LatLng(r.position.lat, r.position.lng)).toList();

    // Recadrage automatique dès que tout est prêt.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFit(points));

    final l = AppLocalizations.of(context);
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
                _maybeFit(points);
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
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
                          child: Icon(
                            Icons.location_on,
                            size: 44,
                            color:
                                report.status == OutageStatus.ongoing
                                    ? AppColors.ongoing
                                    : AppColors.resolved,
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
        ],
      ),
    );
  }
}
