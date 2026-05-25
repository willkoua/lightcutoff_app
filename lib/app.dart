import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/onboarding_gate.dart';
import 'theme/app_theme.dart';
import 'utils/nav_key.dart';

class NjukaApp extends StatelessWidget {
  const NjukaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: MaterialApp(
        title: 'NJUKA',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        navigatorKey: navigatorKey,
        home: const OnboardingGate(),
      ),
    );
  }
}
