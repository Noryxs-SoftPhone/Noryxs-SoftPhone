import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'core/app_controller.dart';
import 'ui/splash.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NoryxsApp());
}

class NoryxsApp extends StatefulWidget {
  const NoryxsApp({super.key});
  @override
  State<NoryxsApp> createState() => _NoryxsAppState();
}

class _NoryxsAppState extends State<NoryxsApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Al cerrar la aplicación: colgar y desregistrar limpiamente.
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      AppController.I.dispose();
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NORYXS Virtual SIP Terminal',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const SplashScreen(),
      );
}
