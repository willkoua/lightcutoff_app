import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_gate.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

/// Affiche l'onboarding au tout premier lancement, puis l'AuthGate.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  static const _prefKey = 'onboarding_seen';

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _seen = prefs.getBool(OnboardingGate._prefKey) ?? false);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingGate._prefKey, true);
    if (!mounted) return;
    setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_seen == null) return const SplashScreen();
    if (_seen == false) return OnboardingScreen(onDone: _finish);
    return const AuthGate();
  }
}
