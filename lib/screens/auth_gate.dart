import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/report_provider.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'splash_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;
    switch (status) {
      case AuthStatus.unknown:
        return const SplashScreen();
      case AuthStatus.authenticated:
        return ChangeNotifierProvider(
          create: (_) => ReportProvider(),
          child: const MainShell(),
        );
      case AuthStatus.awaitingVerification:
        return const EmailVerificationScreen();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
    }
  }
}
