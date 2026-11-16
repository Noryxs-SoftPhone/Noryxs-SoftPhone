import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import 'home.dart';
import 'logo.dart';

/// Compilación (CI: `--dart-define=BUILD=commit`); 'local' en el Mac de desarrollo.
const String kBuild = String.fromEnvironment('BUILD', defaultValue: 'local');
final String kBuildLabel = kBuild.length > 7 ? kBuild.substring(0, 7) : kBuild;

/// Pantalla de arranque: arranca el motor PJSIP mientras muestra el emblema.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  String _status = 'Iniciando motor PJSIP…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final minTime = Future.delayed(const Duration(milliseconds: 2300));
    try {
      await AppController.I.init().timeout(const Duration(seconds: 12));
    } catch (e) {
      // Nunca quedarse colgado en el splash: mostrar el motivo
      try {
        AppController.I.step('ERROR init: $e');
      } catch (_) {}
      if (mounted) setState(() => _status = 'Error al iniciar: $e');
      return;
    }
    if (mounted) setState(() => _status = 'Registrando líneas SIP…');
    await minTime;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, _, _) => const HomeScreen(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _interval(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: curve));

  @override
  Widget build(BuildContext context) {
    final logoIn = _interval(0.0, 0.45, Curves.easeOutBack);
    final glow = _interval(0.25, 0.75);
    final titleIn = _interval(0.30, 0.65);
    final subIn = _interval(0.45, 0.80);
    final bar = _interval(0.40, 1.0, Curves.easeInOutCubic);

    return Scaffold(
      backgroundColor: const Color(0xFF121316),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.0,
            colors: [Color(0xFF24252B), Color(0xFF121316)],
          ),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Opacity(
                  opacity: logoIn.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.82 + 0.18 * logoIn.value,
                    child: NoryxsLogo(size: 108, glow: glow.value),
                  ),
                ),
                const SizedBox(height: 34),
                Opacity(
                  opacity: titleIn.value,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - titleIn.value)),
                    child: GoldText('NORYXS',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 10 + 4 * titleIn.value,
                        )),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: subIn.value,
                  child: const Text('VIRTUAL SIP TERMINAL',
                      style: TextStyle(color: Color(0xFF9A9CA3), fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 4.5)),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 150,
                  height: 1.5,
                  child: Stack(children: [
                    Container(color: Colors.white.withValues(alpha: 0.08)),
                    FractionallySizedBox(
                      widthFactor: bar.value,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0x00CBA765), Color(0xFFF3E2B3), Color(0xFFCBA765)]),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: subIn.value * 0.8,
                  child: Text(_status, style: const TextStyle(color: Color(0xFF6E7078), fontSize: 10.5, letterSpacing: 0.4)),
                ),
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 26,
              child: Opacity(
                opacity: subIn.value * 0.7,
                child: Text('PJSIP · SIP TLS · SRTP · HD VOICE  ·  $kBuildLabel',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF54565D), fontSize: 9.5, letterSpacing: 2.2)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
