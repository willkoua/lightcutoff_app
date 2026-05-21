import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../models/report.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/report_card.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Centre par défaut : Yaoundé.
  static const _fallbackCenter = LatLng(3.848, 11.502);
  static const _minZoom = 3.0;
  static const _maxZoom = 18.0;

  final MapController _controller = MapController();

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _zoom(double delta) {
    final cam = _controller.camera;
    final target = (cam.zoom + delta).clamp(_minZoom, _maxZoom);
    _controller.move(cam.center, target);
  }

  void _openDetails(Report report) {
    final provider = context.read<ReportProvider>();
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
                _snack(ok ? 'Coupure confirmée.' : 'Échec de la confirmation.');
              }
            },
            onResolve: () async {
              Navigator.of(sheetContext).pop();
              final ok = await provider.resolve(report.id);
              if (mounted) {
                _snack(
                  ok ? 'Coupure marquée rétablie.' : 'Échec de la mise à jour.',
                );
              }
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reports = context.watch<ReportProvider>().reports;
    final center =
        reports.isNotEmpty
            ? LatLng(reports.first.position.lat, reports.first.position.lng)
            : _fallbackCenter;

    return Scaffold(
      appBar: AppBar(title: const Text('Carte des coupures')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: center,
              initialZoom: reports.isNotEmpty ? 12 : 6,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.lightcutoff_app',
                maxZoom: 19,
              ),
              MarkerLayer(
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
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: () => _zoom(1),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: () => _zoom(-1),
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
