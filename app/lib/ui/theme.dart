import 'package:flutter/material.dart';

/// Paleta NORYXS (tomada del diseño HTML de referencia).
/// Modo claro y oscuro: cada color es un getter que mira [night].
class NxColors {
  /// true = modo oscuro (lo fija la app según la preferencia y el sistema).
  static bool night = false;
  static Color _c(int light, int dark) => Color(night ? dark : light);

  // Base
  static Color get background => _c(0xFFFFFFFF, 0xFF121316);
  static Color get card => _c(0xFFFFFFFF, 0xFF1B1C20);
  static Color get surface => _c(0xFFF9FAFB, 0xFF222328);
  static Color get surfaceHover => _c(0xFFF3F4F6, 0xFF2B2C32);
  static Color get border => _c(0xFFE5E7EB, 0xFF34353C);
  static Color get text => _c(0xFF18181B, 0xFFECECEE); // charcoal
  /// Fondo de botones y piezas "oscuras" (en modo oscuro se aclaran un poco).
  static Color get dark => _c(0xFF18181B, 0xFF3A3B42);
  static Color get muted => _c(0xFF71717A, 0xFFA1A1AA);
  static Color get gray400 => _c(0xFF9CA3AF, 0xFF7C7F87);
  static Color get gray500 => _c(0xFF6B7280, 0xFF9A9CA3);
  static Color get gray600 => _c(0xFF4B5563, 0xFFB4B6BC);
  static Color get gray700 => _c(0xFF374151, 0xFFCFD1D6);
  static Color get faint => _c(0xFF9CA3AF, 0xFF7C7F87);

  // Oro NORYXS
  static Color get gold => _c(0xFFC5A059, 0xFFD4B26E);
  static Color get goldDark => _c(0xFF9A7B3E, 0xFFE2C78F); // texto de acento
  static Color get goldSoft => _c(0xFFFAF5EB, 0xFF2E2819); // fondo suave
  static Color get goldBorder => _c(0x66C5A059, 0x80D4B26E);
  static Color get goldBar => _c(0xFFE6D9BC, 0xFF4A3F27);

  // Estados
  static Color get green => _c(0xFF10B981, 0xFF10B981); // emerald-500
  static Color get green600 => _c(0xFF059669, 0xFF34D399);
  static Color get greenText => _c(0xFF047857, 0xFF6EE7B7); // emerald-700
  static Color get greenSoft => _c(0xFFECFDF5, 0xFF0F2A22);
  static Color get greenBorder => _c(0xFFA7F3D0, 0xFF1F5A47);
  static Color get red => _c(0xFFDC2626, 0xFFEF4444); // red-600
  static Color get red500 => _c(0xFFEF4444, 0xFFF87171);
  static Color get redText => _c(0xFFB91C1C, 0xFFFCA5A5);
  static Color get redSoft => _c(0xFFFEF2F2, 0xFF3A1A1A);
  static Color get redBorder => _c(0xFFFECACA, 0xFF6B2A2A);
  static Color get amber => _c(0xFFF59E0B, 0xFFF59E0B);
  static Color get amberText => _c(0xFF92400E, 0xFFFCD34D);
  static Color get amberSoft => _c(0xFFFFFBEB, 0xFF3A2E12);
  static Color get amberBorder => _c(0xFFFBBF24, 0xFF7A5A14);
  static Color get sky => _c(0xFF0EA5E9, 0xFF38BDF8);
  static Color get skyText => _c(0xFF0369A1, 0xFF7DD3FC);
  static Color get skySoft => _c(0xFFE0F2FE, 0xFF0E2A3A);
}

const kMono = 'JetBrainsMono';
const kSans = 'Inter';

/// Marca el idioma dentro del tema: al cambiar de idioma cambia el tema y la interfaz se repinta.
class LangTheme extends ThemeExtension<LangTheme> {
  const LangTheme(this.lang);
  final String lang;
  @override
  LangTheme copyWith({String? lang}) => LangTheme(lang ?? this.lang);
  @override
  LangTheme lerp(LangTheme? other, double t) => other ?? this;
}

ThemeData buildTheme({String lang = 'es'}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: NxColors.night ? Brightness.dark : Brightness.light,
    fontFamily: kSans,
    scaffoldBackgroundColor: NxColors.background,
    colorScheme: ColorScheme.fromSeed(seedColor: NxColors.gold, brightness: NxColors.night ? Brightness.dark : Brightness.light, surface: NxColors.card),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.compact,
    extensions: [LangTheme(lang)],
  );
  OutlineInputBorder ob(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: NxColors.text, displayColor: NxColors.text, fontFamily: kSans),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NxColors.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      hintStyle: TextStyle(color: NxColors.gray400, fontSize: 12),
      labelStyle: TextStyle(color: NxColors.gray500, fontSize: 12),
      border: ob(NxColors.border),
      enabledBorder: ob(NxColors.border),
      focusedBorder: ob(NxColors.gold, 1.2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: NxColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(fontFamily: kSans, color: NxColors.text, fontSize: 15, fontWeight: FontWeight.w700),
      contentTextStyle: TextStyle(fontFamily: kSans, color: NxColors.text, fontSize: 12.5),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: NxColors.card,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(fontFamily: kSans, fontSize: 12, color: NxColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: NxColors.border)),
    ),
    sliderTheme: SliderThemeData(
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
