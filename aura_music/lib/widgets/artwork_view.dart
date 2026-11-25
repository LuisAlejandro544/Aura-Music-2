// =============================================================================
// artwork_view.dart — Renderizador rápido de carátulas locales con fallback cálido
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Muestra la carátula incrustada cacheada en disco usando decodificación
//   redimensionada (cacheWidth) para ahorrar RAM y mantener el scroll a 120 fps.
//   Si el archivo local no trae portada, dibuja una cubierta estilizada tipo
//   vinilo/funda cálida usando un tinte determinista por álbum o título.
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/aura_theme.dart';

class ArtworkView extends StatelessWidget {
  const ArtworkView({
    super.key,
    required this.artworkPath,
    required this.seed,
    this.size = 54,
    this.borderRadius = 14,
    this.showShadow = false,
  });

  final String? artworkPath;
  final String seed;
  final double size;
  final double borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final hasFile =
        artworkPath != null && artworkPath!.isNotEmpty && File(artworkPath!).existsSync();
    final tint = AuraTheme.warmTintForSeed(seed);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: tint,
        border: Border.all(
          color: AuraColors.border.withValues(alpha: 0.7),
          width: 1,
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AuraColors.textPrimary.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasFile
          ? Image.file(
              File(artworkPath!),
              fit: BoxFit.cover,
              cacheWidth: (size * 2.5).round(),
              errorBuilder: (_, __, ___) => _FallbackDiscArt(
                seed: seed,
                size: size,
                tint: tint,
              ),
            )
          : _FallbackDiscArt(
              seed: seed,
              size: size,
              tint: tint,
            ),
    );
  }
}

class _FallbackDiscArt extends StatelessWidget {
  const _FallbackDiscArt({
    required this.seed,
    required this.size,
    required this.tint,
  });

  final String seed;
  final double size;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final iconSize = (size * 0.42).clamp(18.0, 72.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint,
                Color.lerp(tint, AuraColors.accent, 0.22) ?? tint,
              ],
            ),
          ),
        ),
        if (size >= 70)
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AuraColors.textPrimary.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
          ),
        Icon(
          Icons.music_note_rounded,
          size: iconSize,
          color: AuraColors.textPrimary.withValues(alpha: 0.65),
        ),
      ],
    );
  }
}
