import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Splash Flutter volontairement **identique** au splash natif (ampoule
/// `njuka_splash.png` centrée sur fond charbon) : la transition natif → Flutter
/// est invisible, seul le **halo ambre s'allume et pulse** autour de l'ampoule.
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
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = _pulse.value; // 0 → 1
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06 + 0.24 * t),
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
    );
  }
}
