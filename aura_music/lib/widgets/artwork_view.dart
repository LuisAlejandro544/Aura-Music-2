// =============================================================================
// artwork_view.dart — Renderizador rápido de carátulas locales y remotas
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Muestra la carátula incrustada cacheada en disco o una miniatura HTTP/HTTPS
//   de Explorar usando decodificación redimensionada (cacheWidth) para ahorrar
//   RAM y mantener el scroll fluido. Si no hay portada o falla la red, dibuja
//   una cubierta estilizada tipo vinilo/funda cálida determinista.
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
    final c = AuraTheme.of(context);
    final rawPath = artworkPath?.trim() ?? '';
    final isNetwork =
        rawPath.startsWith('https://') || rawPath.startsWith('http://');
    final hasFile =
        !isNetwork && rawPath.isNotEmpty && File(rawPath).existsSync();
    final tint = AuraTheme.warmTintForSeed(seed, isDark: c.isDark);
    final decodeWidth = (size * 2.5).round().clamp(64, 960);

    Widget artworkChild;
    if (isNetwork) {
      artworkChild = Image.network(
        rawPath,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        errorBuilder: (_, __, ___) => _FallbackDiscArt(
          seed: seed,
          size: size,
          tint: tint,
        ),
      );
    } else if (hasFile) {
      artworkChild = Image.file(
        File(rawPath),
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        errorBuilder: (_, __, ___) => _FallbackDiscArt(
          seed: seed,
          size: size,
          tint: tint,
        ),
      );
    } else {
      artworkChild = _FallbackDiscArt(
        seed: seed,
        size: size,
        tint: tint,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: tint,
        border: Border.all(
          color: c.border.withValues(alpha: 0.7),
          width: 1,
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: artworkChild,
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
    final c = AuraTheme.of(context);
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
                Color.lerp(tint, c.accent, 0.22) ?? tint,
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
                color: c.textPrimary.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
          ),
        Icon(
          Icons.music_note_rounded,
          size: iconSize,
          color: c.textPrimary.withValues(alpha: 0.65),
        ),
      ],
    );
  }
}
