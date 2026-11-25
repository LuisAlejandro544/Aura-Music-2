// =============================================================================
// mini_player.dart — Mini reproductor persistente con gestos fluidos
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Se muestra flotando suavemente encima de la barra inferior en todas las
//   pantallas principales. Incluye:
//   - Barra fina de progreso en tiempo real.
//   - Gesto horizontal (swipe izquierda/derecha) para cambiar de pista al vuelo.
//   - Gesto de toque o arrastre hacia arriba para abrir FullPlayerScreen.
//   - Botón inmediato de favorito y Play/Pause.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/aura_theme.dart';
import '../state/library_provider.dart';
import '../state/player_provider.dart';
import 'artwork_view.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    required this.onExpand,
  });

  final VoidCallback onExpand;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _dragOffsetX = 0;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final library = context.read<LibraryProvider>();
    final bgTint = Color.lerp(
      c.surfaceElevated,
      AuraTheme.warmTintForSeed(track.album, isDark: c.isDark),
      0.28,
    )!;

    return GestureDetector(
      onTap: widget.onExpand,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -240) {
          HapticFeedback.selectionClick();
          widget.onExpand();
        }
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffsetX = (_dragOffsetX + details.delta.dx).clamp(-56.0, 56.0);
        });
      },
      onHorizontalDragEnd: (details) {
        final vx = details.primaryVelocity ?? 0;
        if (_dragOffsetX < -28 || vx < -320) {
          HapticFeedback.lightImpact();
          player.skipNext();
        } else if (_dragOffsetX > 28 || vx > 320) {
          HapticFeedback.lightImpact();
          player.skipPrevious();
        }
        setState(() => _dragOffsetX = 0);
      },
      onHorizontalDragCancel: () => setState(() => _dragOffsetX = 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        transform: Matrix4.translationValues(_dragOffsetX * 0.45, 0, 0),
        decoration: BoxDecoration(
          color: bgTint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra fina de progreso superior
            LinearProgressIndicator(
              value: player.progress,
              minHeight: 2.5,
              backgroundColor: c.border.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  Hero(
                    tag: 'aura_current_artwork',
                    child: ArtworkView(
                      artworkPath: track.artworkPath,
                      seed: '${track.album}_${track.title}',
                      size: 46,
                      borderRadius: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      library.toggleFavorite(track.id);
                    },
                    icon: Icon(
                      track.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: track.isFavorite ? c.accent : c.textSecondary,
                      size: 22,
                    ),
                    tooltip: 'Favorito',
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        player.togglePlayPause();
                      },
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      tooltip: player.isPlaying ? 'Pausar' : 'Reproducir',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
