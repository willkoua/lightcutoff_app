import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/report_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/report_card.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'report_form_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final reports = context.watch<ReportProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coupures signalées'),
        actions: [
          IconButton(
            tooltip: 'Voir sur la carte',
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              final provider = context.read<ReportProvider>();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: provider,
                    child: const MapScreen(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Mon profil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final provider = context.read<ReportProvider>();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: provider,
                child: const ReportFormScreen(),
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Signaler'),
      ),
      body: Builder(
        builder: (_) {
          if (reports.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (reports.error != null) {
            return _Message(
              icon: Icons.error_outline,
              text: reports.error!,
            );
          }
          if (reports.reports.isEmpty) {
            return const _Message(
              icon: Icons.check_circle_outline,
              text: 'Aucune coupure signalée pour le moment.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: reports.reports.length,
            itemBuilder: (context, i) {
              final report = reports.reports[i];
              return ReportCard(
                report: report,
                isAuthor: reports.isAuthor(report),
                onConfirm: () async {
                  final ok = await reports.confirm(report.id);
                  if (context.mounted) {
                    _snack(context,
                        ok ? 'Coupure confirmée.' : 'Échec de la confirmation.');
                  }
                },
                onResolve: () async {
                  final ok = await reports.resolve(report.id);
                  if (context.mounted) {
                    _snack(context,
                        ok ? 'Coupure marquée rétablie.' : 'Échec de la mise à jour.');
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.gray),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray),
            ),
          ],
        ),
      ),
    );
  }
}
