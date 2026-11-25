// =============================================================================
// aura_theme.dart — Sistema de diseño "Acoustic Warmth" (Claro y Oscuro)
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Define la paleta de colores cálida, orgánica y de alto agrado visual tanto
//   en Modo Claro (crema alabastro, avena cálida, carbón espresso) como en Modo
//   Oscuro (carbón cálido profundo, madera espresso, crema suave).
//   Expone `AuraPalette` mediante ThemeExtension y `AuraTheme.of(context)` para
//   que toda pantalla y hoja modal responda instantáneamente al cambio de tema.
// =============================================================================

import 'package:flutter/material.dart';

class AuraColors {
  const AuraColors._();

  // Superficies principales (Modo Claro cálido)
  static const Color background = Color(0xFFF9F6F0); // Crema Alabastro
  static const Color surface = Color(0xFFF0EBE1); // Avena Cálida
  static const Color surfaceElevated = Color(0xFFFFFFFF); // Tarjeta limpia elevada
  static const Color surfacePressed = Color(0xFFE7E0D3);

  // Texto e iconografía
  static const Color textPrimary = Color(0xFF2C2524); // Carbón Espresso
  static const Color textSecondary = Color(0xFF8C827B); // Taupe Suave
  static const Color textMuted = Color(0xFFB0A79F);

  // Acentos cálidos principales
  static const Color accent = Color(0xFFD96B43); // Terracota / Coral Cálido
  static const Color accentSoft = Color(0xFFFBEAE3);
  static const Color amber = Color(0xFFE5A93B); // Ámbar / Ocre Suave
  static const Color amberSoft = Color(0xFFFDF3DF);
  static const Color sage = Color(0xFF3B8A6E); // Verde Salvia para lossless/FLAC
  static const Color sageSoft = Color(0xFFE4F2EC);

  // Bordes y divisores sutiles
  static const Color border = Color(0xFFE3DED4);
  static const Color shadow = Color(0x162C2524);
}

class AuraDarkColors {
  const AuraDarkColors._();

  // Superficies principales (Modo Oscuro "Acoustic Warmth Dark")
  static const Color background = Color(0xFF171413); // Carbón Espresso Profundo
  static const Color surface = Color(0xFF211D1B); // Madera Oscura Cálida
  static const Color surfaceElevated = Color(0xFF2A2522); // Tarjeta elevada
  static const Color surfacePressed = Color(0xFF352E2B);

  // Texto e iconografía
  static const Color textPrimary = Color(0xFFF4EFE8); // Crema Suave
  static const Color textSecondary = Color(0xFFB3AAA2); // Arena Cálida
  static const Color textMuted = Color(0xFF857C75);

  // Acentos cálidos adaptados a fondo oscuro
  static const Color accent = Color(0xFFE07A54); // Terracota luminoso
  static const Color accentSoft = Color(0xFF3D251E);
  static const Color amber = Color(0xFFEBB44D); // Ámbar cálido
  static const Color amberSoft = Color(0xFF382D18);
  static const Color sage = Color(0xFF4DA887); // Verde salvia legible
  static const Color sageSoft = Color(0xFF1D332B);

  // Bordes y sombras
  static const Color border = Color(0xFF36302C);
  static const Color shadow = Color(0x4D000000);
}

@immutable
class AuraPalette extends ThemeExtension<AuraPalette> {
  const AuraPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfacePressed,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.amber,
    required this.amberSoft,
    required this.sage,
    required this.sageSoft,
    required this.border,
    required this.shadow,
    required this.chipSelectedBg,
    required this.chipSelectedFg,
    required this.scrim,
    required this.errorBg,
    required this.errorBorder,
    required this.errorText,
    required this.terminalBg,
    required this.terminalText,
  });

  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfacePressed;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color amber;
  final Color amberSoft;
  final Color sage;
  final Color sageSoft;
  final Color border;
  final Color shadow;
  final Color chipSelectedBg;
  final Color chipSelectedFg;
  final Color scrim;
  final Color errorBg;
  final Color errorBorder;
  final Color errorText;
  final Color terminalBg;
  final Color terminalText;

  static const AuraPalette light = AuraPalette(
    isDark: false,
    background: AuraColors.background,
    surface: AuraColors.surface,
    surfaceElevated: AuraColors.surfaceElevated,
    surfacePressed: AuraColors.surfacePressed,
    textPrimary: AuraColors.textPrimary,
    textSecondary: AuraColors.textSecondary,
    textMuted: AuraColors.textMuted,
    accent: AuraColors.accent,
    accentSoft: AuraColors.accentSoft,
    amber: AuraColors.amber,
    amberSoft: AuraColors.amberSoft,
    sage: AuraColors.sage,
    sageSoft: AuraColors.sageSoft,
    border: AuraColors.border,
    shadow: AuraColors.shadow,
    chipSelectedBg: AuraColors.textPrimary,
    chipSelectedFg: Colors.white,
    scrim: Color(0x592C2524),
    errorBg: Color(0xFFF9E4E1),
    errorBorder: Color(0xFFE7B6B0),
    errorText: Color(0xFF8D2B20),
    terminalBg: AuraColors.textPrimary,
    terminalText: AuraColors.background,
  );

  static const AuraPalette dark = AuraPalette(
    isDark: true,
    background: AuraDarkColors.background,
    surface: AuraDarkColors.surface,
    surfaceElevated: AuraDarkColors.surfaceElevated,
    surfacePressed: AuraDarkColors.surfacePressed,
    textPrimary: AuraDarkColors.textPrimary,
    textSecondary: AuraDarkColors.textSecondary,
    textMuted: AuraDarkColors.textMuted,
    accent: AuraDarkColors.accent,
    accentSoft: AuraDarkColors.accentSoft,
    amber: AuraDarkColors.amber,
    amberSoft: AuraDarkColors.amberSoft,
    sage: AuraDarkColors.sage,
    sageSoft: AuraDarkColors.sageSoft,
    border: AuraDarkColors.border,
    shadow: AuraDarkColors.shadow,
    chipSelectedBg: AuraDarkColors.textPrimary,
    chipSelectedFg: AuraDarkColors.background,
    scrim: Color(0x99000000),
    errorBg: Color(0xFF3A1E1B),
    errorBorder: Color(0xFF6B342E),
    errorText: Color(0xFFF4A59B),
    terminalBg: Color(0xFF0E0C0B),
    terminalText: AuraDarkColors.textPrimary,
  );

  @override
  AuraPalette copyWith({
    bool? isDark,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfacePressed,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
    Color? amber,
    Color? amberSoft,
    Color? sage,
    Color? sageSoft,
    Color? border,
    Color? shadow,
    Color? chipSelectedBg,
    Color? chipSelectedFg,
    Color? scrim,
    Color? errorBg,
    Color? errorBorder,
    Color? errorText,
    Color? terminalBg,
    Color? terminalText,
  }) {
    return AuraPalette(
      isDark: isDark ?? this.isDark,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      amber: amber ?? this.amber,
      amberSoft: amberSoft ?? this.amberSoft,
      sage: sage ?? this.sage,
      sageSoft: sageSoft ?? this.sageSoft,
      border: border ?? this.border,
      shadow: shadow ?? this.shadow,
      chipSelectedBg: chipSelectedBg ?? this.chipSelectedBg,
      chipSelectedFg: chipSelectedFg ?? this.chipSelectedFg,
      scrim: scrim ?? this.scrim,
      errorBg: errorBg ?? this.errorBg,
      errorBorder: errorBorder ?? this.errorBorder,
      errorText: errorText ?? this.errorText,
      terminalBg: terminalBg ?? this.terminalBg,
      terminalText: terminalText ?? this.terminalText,
    );
  }

  @override
  AuraPalette lerp(ThemeExtension<AuraPalette>? other, double t) {
    if (other is! AuraPalette) return this;
    return AuraPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
              surfaceElevated,
      surfacePressed:
          Color.lerp(surfacePressed, other.surfacePressed, t) ?? surfacePressed,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      amber: Color.lerp(amber, other.amber, t) ?? amber,
      amberSoft: Color.lerp(amberSoft, other.amberSoft, t) ?? amberSoft,
      sage: Color.lerp(sage, other.sage, t) ?? sage,
      sageSoft: Color.lerp(sageSoft, other.sageSoft, t) ?? sageSoft,
      border: Color.lerp(border, other.border, t) ?? border,
      shadow: Color.lerp(shadow, other.shadow, t) ?? shadow,
      chipSelectedBg:
          Color.lerp(chipSelectedBg, other.chipSelectedBg, t) ?? chipSelectedBg,
      chipSelectedFg:
          Color.lerp(chipSelectedFg, other.chipSelectedFg, t) ?? chipSelectedFg,
      scrim: Color.lerp(scrim, other.scrim, t) ?? scrim,
      errorBg: Color.lerp(errorBg, other.errorBg, t) ?? errorBg,
      errorBorder: Color.lerp(errorBorder, other.errorBorder, t) ?? errorBorder,
      errorText: Color.lerp(errorText, other.errorText, t) ?? errorText,
      terminalBg: Color.lerp(terminalBg, other.terminalBg, t) ?? terminalBg,
      terminalText:
          Color.lerp(terminalText, other.terminalText, t) ?? terminalText,
    );
  }
}

class AuraTheme {
  const AuraTheme._();

  static AuraPalette of(BuildContext context) {
    final ext = Theme.of(context).extension<AuraPalette>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark
        ? AuraPalette.dark
        : AuraPalette.light;
  }

  static ThemeData buildLightTheme() {
    const colorScheme = ColorScheme.light(
      primary: AuraColors.accent,
      onPrimary: Colors.white,
      secondary: AuraColors.amber,
      onSecondary: AuraColors.textPrimary,
      surface: AuraColors.surface,
      onSurface: AuraColors.textPrimary,
      outline: AuraColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AuraColors.background,
      splashColor: AuraColors.accent.withValues(alpha: 0.08),
      highlightColor: AuraColors.surfacePressed.withValues(alpha: 0.5),
      extensions: const <ThemeExtension<dynamic>>[
        AuraPalette.light,
      ],
      cardTheme: CardThemeData(
        color: AuraColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AuraColors.border, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AuraColors.background,
        foregroundColor: AuraColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AuraColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AuraColors.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AuraColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AuraColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          color: AuraColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: AuraColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: AuraColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: TextStyle(
          color: AuraColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static ThemeData buildDarkTheme() {
    const colorScheme = ColorScheme.dark(
      primary: AuraDarkColors.accent,
      onPrimary: Colors.white,
      secondary: AuraDarkColors.amber,
      onSecondary: AuraDarkColors.background,
      surface: AuraDarkColors.surface,
      onSurface: AuraDarkColors.textPrimary,
      outline: AuraDarkColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AuraDarkColors.background,
      splashColor: AuraDarkColors.accent.withValues(alpha: 0.14),
      highlightColor: AuraDarkColors.surfacePressed.withValues(alpha: 0.55),
      extensions: const <ThemeExtension<dynamic>>[
        AuraPalette.dark,
      ],
      cardTheme: CardThemeData(
        color: AuraDarkColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AuraDarkColors.border, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AuraDarkColors.background,
        foregroundColor: AuraDarkColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AuraDarkColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AuraDarkColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AuraDarkColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: AuraDarkColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          color: AuraDarkColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: AuraDarkColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: AuraDarkColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        labelMedium: TextStyle(
          color: AuraDarkColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// Genera un tono cálido determinista para portadas sin imagen incrustada o
  /// tintes suaves en el reproductor completo, adaptado a modo claro u oscuro.
  static Color warmTintForSeed(String seed, {bool isDark = false}) {
    const lightSwatches = <Color>[
      Color(0xFFEBD4C5), // Terracota pálido
      Color(0xFFEFE1C4), // Ámbar arena
      Color(0xFFD7E4DD), // Salvia cálido
      Color(0xFFE7D8DE), // Rosa arcilla
      Color(0xFFDCE0EA), // Pizarra suave
      Color(0xFFEAE0D0), // Lino dorado
    ];
    const darkSwatches = <Color>[
      Color(0xFF3E2B24), // Terracota tostado oscuro
      Color(0xFF3C3321), // Ámbar espresso oscuro
      Color(0xFF23362F), // Salvia profundo
      Color(0xFF392930), // Arcilla ahumada
      Color(0xFF282E3A), // Pizarra cálida oscura
      Color(0xFF362F26), // Lino carbón
    ];
    final swatches = isDark ? darkSwatches : lightSwatches;
    if (seed.isEmpty) return swatches.first;
    final hash =
        seed.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return swatches[hash % swatches.length];
  }
}
