import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_gate.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

/// Affiche l'onboarding au tout premier lancement, puis l'AuthGate.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  /// Clé `SharedPreferences` du drapeau « onboarding déjà vu ». Exposée
  /// publiquement pour que l'écran Paramètres puisse la **réinitialiser**
  /// (« Revoir le tutoriel ») sans dépendre de l'implémentation interne.
  static const prefKey = 'onboarding_seen';

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

  /// Durée minimale d'affichage du splash animé au démarrage, pour qu'il soit
  /// visible même quand la session se résout instantanément.
  static const _minSplash = Duration(seconds: 2);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(OnboardingGate.prefKey) ?? false;
    // Laisse le halo du splash respirer un minimum avant d'enchaîner.
    await Future<void>.delayed(_minSplash);
    if (!mounted) return;
    setState(() => _seen = seen);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingGate.prefKey, true);
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
