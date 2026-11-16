import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'core/app_controller.dart';
import 'core/i18n.dart';
import 'core/ui_prefs.dart';
import 'ui/splash.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UiPrefs.I.load();
  runApp(const NoryxsApp());
}

class NoryxsApp extends StatefulWidget {
  const NoryxsApp({super.key});
  @override
  State<NoryxsApp> createState() => _NoryxsAppState();
}

class _NoryxsAppState extends State<NoryxsApp> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UiPrefs.I.addListener(_restyle);
    // Al cerrar la aplicación: colgar y desregistrar limpiamente.
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      AppController.I.dispose();
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UiPrefs.I.removeListener(_restyle);
    _lifecycle.dispose();
    super.dispose();
  }

  void _restyle() => setState(() {});

  // Modo automático: el sistema ha cambiado entre claro y oscuro
  @override
  void didChangePlatformBrightness() => _restyle();

  // Idioma automático: el usuario ha cambiado el idioma del sistema
  @override
  void didChangeLocales(List<Locale>? locales) => _restyle();

  @override
  Widget build(BuildContext context) {
    NxColors.night = UiPrefs.I.isNight(WidgetsBinding.instance.platformDispatcher.platformBrightness);
    I18n.lang = I18n.resolve(UiPrefs.I.lang);
    return MaterialApp(
        title: 'NORYXS Virtual SIP Terminal',
        debugShowCheckedModeBanner: false,
        navigatorKey: AppController.navigatorKey,
        theme: buildTheme(lang: I18n.lang),
        home: const SplashScreen(),
      );
  }
}
