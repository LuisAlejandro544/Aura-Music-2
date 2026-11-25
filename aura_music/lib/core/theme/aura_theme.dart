// =============================================================================
// aura_theme.dart — Sistema de diseño en modo claro "Acoustic Warmth"
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Define la paleta de colores cálida, orgánica y de alto agrado visual
//   (crema alabastro, avena cálida, carbón espresso, terracota coral y ámbar
//   suave) junto con sombras, radios de borde y tipografía de Aura Music.
//   Evita colores neón/cyberpunk y mantiene un equilibrio rico y táctil (sin
//   caer en minimalismo extremo ni pantallas vacías).
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

class AuraTheme {
  const AuraTheme._();

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

  /// Genera un tono cálido determinista para portadas sin imagen incrustada o
  /// tintes suaves en el reproductor completo.
  static Color warmTintForSeed(String seed) {
    const swatches = <Color>[
      Color(0xFFEBD4C5), // Terracota pálido
      Color(0xFFEFE1C4), // Ámbar arena
      Color(0xFFD7E4DD), // Salvia cálido
      Color(0xFFE7D8DE), // Rosa arcilla
      Color(0xFFDCE0EA), // Pizarra suave
      Color(0xFFEAE0D0), // Lino dorado
    ];
    if (seed.isEmpty) return swatches.first;
    final hash = seed.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return swatches[hash % swatches.length];
  }
}
