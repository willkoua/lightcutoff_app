import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../providers/report_provider.dart';
import '../theme/app_colors.dart';

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

  Future<void> _submit() async {
    final provider = context.read<ReportProvider>();
    final error = await provider.submitReport(
      cause: _cause,
      description: _description.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Coupure signalée. Merci !')),
        );
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
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
