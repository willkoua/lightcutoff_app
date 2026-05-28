import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _checking = false;
  bool _resending = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final verified = await context.read<AuthProvider>().refreshVerification();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!verified) {
      _snack(AppLocalizations.of(context).emailVerificationNotYet);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    await context.read<AuthProvider>().resendVerificationEmail();
    if (!mounted) return;
    setState(() => _resending = false);
    _snack(AppLocalizations.of(context).emailVerificationResent);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final email = auth.pendingEmail ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(l.emailVerificationTitle),
        actions: [
          IconButton(
            tooltip: l.tooltipLogout,
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.mark_email_unread_outlined,
                  size: 72,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  l.emailVerificationHeading,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.emailVerificationBody(email),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.gray),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _checking ? null : _check,
                  child:
                      _checking
                          ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.dark,
                            ),
                          )
                          : Text(l.emailVerificationCheckButton),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _resending ? null : _resend,
                  child: Text(l.emailVerificationResendAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
