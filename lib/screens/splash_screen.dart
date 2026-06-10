import 'package:flutter/material.dart';
import 'package:lightcutoff_app/l10n/generated/app_localizations.dart';

import '../theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    // Halo « respirant » : aller-retour continu (1,4 s) avec une courbe douce.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Stack(
        children: [
          // Ampoule = MÊME image que le splash natif (`njuka_splash.png`),
          // centrée sur l'écran → la transition natif → Flutter est invisible,
          // seul le halo s'allume.
          Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final t = _pulse.value; // 0 → 1
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(
                          alpha: 0.06 + 0.24 * t,
                        ),
                        blurRadius: 22 + 40 * t,
                        spreadRadius: 4 + 16 * t,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Image.asset(
                'assets/splash/njuka_splash.png',
                width: 140,
                height: 140,
              ),
            ),
          ),
          // Nom + slogan + indicateur, sous l'ampoule (n'affecte pas la
          // position de l'ampoule, qui reste centrée comme le splash natif).
          Align(
            alignment: const Alignment(0, 0.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.appName,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.splashTagline,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 28),
                const CircularProgressIndicator(color: AppColors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
