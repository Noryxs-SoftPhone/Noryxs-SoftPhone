import 'package:flutter/material.dart';

/// Paleta NORYXS (tomada del diseño HTML de referencia).
class NxColors {
  // Base
  static const background = Color(0xFFFFFFFF);
  static const card = Colors.white;
  static const surface = Color(0xFFF9FAFB);
  static const surfaceHover = Color(0xFFF3F4F6);
  static const border = Color(0xFFE5E7EB);
  static const text = Color(0xFF18181B); // charcoal
  static const dark = Color(0xFF18181B);
  static const muted = Color(0xFF71717A);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const faint = Color(0xFF9CA3AF);

  // Oro
  static const gold = Color(0xFFC5A059);
  static const goldDark = Color(0xFF9A7B3E);
  static const goldSoft = Color(0xFFFAF5EB); // goldLight
  static const goldBorder = Color(0x66C5A059);
  static const goldBar = Color(0xFFE6D9BC);

  // Estados
  static const green = Color(0xFF10B981); // emerald-500
  static const green600 = Color(0xFF059669);
  static const greenText = Color(0xFF047857); // emerald-700
  static const greenSoft = Color(0xFFECFDF5);
  static const greenBorder = Color(0xFFA7F3D0);
  static const red = Color(0xFFDC2626); // red-600
  static const red500 = Color(0xFFEF4444);
  static const redText = Color(0xFFB91C1C);
  static const redSoft = Color(0xFFFEF2F2);
  static const redBorder = Color(0xFFFECACA);
  static const amber = Color(0xFFF59E0B);
  static const amberText = Color(0xFF92400E);
  static const amberSoft = Color(0xFFFFFBEB);
  static const amberBorder = Color(0xFFFBBF24);
  static const sky = Color(0xFF0EA5E9);
  static const skyText = Color(0xFF0369A1);
  static const skySoft = Color(0xFFE0F2FE);
}

const kMono = 'JetBrainsMono';
const kSans = 'Inter';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: kSans,
    scaffoldBackgroundColor: NxColors.background,
    colorScheme: ColorScheme.fromSeed(seedColor: NxColors.gold, brightness: Brightness.light, surface: Colors.white),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.compact,
  );
  OutlineInputBorder ob(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: NxColors.text, displayColor: NxColors.text, fontFamily: kSans),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      hintStyle: const TextStyle(color: NxColors.gray400, fontSize: 12),
      labelStyle: const TextStyle(color: NxColors.gray500, fontSize: 12),
      border: ob(NxColors.border),
      enabledBorder: ob(NxColors.border),
      focusedBorder: ob(NxColors.gold, 1.2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(fontFamily: kSans, color: NxColors.text, fontSize: 15, fontWeight: FontWeight.w700),
      contentTextStyle: const TextStyle(fontFamily: kSans, color: NxColors.text, fontSize: 12.5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      textStyle: const TextStyle(fontFamily: kSans, fontSize: 12, color: NxColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: NxColors.border)),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: NxColors.dark,
      thumbColor: NxColors.dark,
      inactiveTrackColor: NxColors.border,
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : NxColors.gray400),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? NxColors.gold : NxColors.surfaceHover),
      trackOutlineColor: WidgetStateProperty.all(NxColors.border),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: const TextStyle(fontFamily: kSans, fontSize: 11, color: Colors.white),
      decoration: BoxDecoration(color: NxColors.dark, borderRadius: BorderRadius.circular(8)),
    ),
  );
}
