// =============================================================================
// full_player_screen.dart — Reproductor completo con gestos fluidos
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Pantalla dedicada del reproductor Aura Music en modo claro cálido:
//   - Fondo dinámico sutilmente teñido según la pista actual.
//   - Gesto vertical hacia abajo para minimizar suavemente al mini reproductor.
//   - Gesto horizontal sobre la carátula para saltar a siguiente o anterior.
//   - Animación elástica al pausar/reproducir en la carátula.
//   - Barra de progreso táctil, controles completos (Shuffle, Prev, Play/Pause,
//     Next, Repeat), insignia técnica (FLAC/MP3 + ExoPlayer) y acceso a la cola.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/artwork_view.dart';
import '../../widgets/sheets/queue_sheet.dart';
import '../../widgets/sheets/track_options_sheet.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  double _dragY = 0;
  double _artDragX = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.read<LibraryProvider>();
    final track = player.currentTrack;

    if (track == null) {
      return const Scaffold(
        backgroundColor: AuraColors.background,
        body: Center(child: Text('No hay ninguna canción activa')),
      );
    }

    final tint = AuraTheme.warmTintForSeed(track.album);
    final totalMs = player.duration.inMilliseconds.clamp(1, 36000000);
    final currentMs = player.position.inMilliseconds.clamp(0, totalMs);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.delta.dy > 0 || _dragY > 0) {
          setState(() {
            _dragY = (_dragY + details.delta.dy).clamp(0.0, 260.0);
          });
        }
      },
      onVerticalDragEnd: (details) {
        final vy = details.primaryVelocity ?? 0;
        if (_dragY > 95 || vy > 520) {
          Navigator.of(context).pop();
        } else {
          setState(() => _dragY = 0);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _dragY, 0),
        child: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(AuraColors.background, tint, 0.55)!,
                  AuraColors.background,
                  AuraColors.surface.withValues(alpha: 0.65),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    // Indicador de arrastre superior
                    Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: AuraColors.textPrimary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Cabecera superior
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                          tooltip: 'Minimizar reproductor',
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'REPRODUCIENDO DESDE',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                  color: AuraColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.folderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AuraColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => showTrackOptionsSheet(context, track),
                          icon: const Icon(Icons.more_horiz_rounded),
                          tooltip: 'Opciones de pista',
                        ),
                      ],
                    ),

                    const Spacer(flex: 2),

                    // Carátula central con gesto horizontal fluido y escala viva
                    GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _artDragX = (_artDragX + details.delta.dx).clamp(-90.0, 90.0);
                        });
                      },
                      onHorizontalDragEnd: (details) {
                        final vx = details.primaryVelocity ?? 0;
                        if (_artDragX < -40 || vx < -380) {
                          HapticFeedback.lightImpact();
                          player.skipNext();
                        } else if (_artDragX > 40 || vx > 380) {
                          HapticFeedback.lightImpact();
                          player.skipPrevious();
                        }
                        setState(() => _artDragX = 0);
                      },
                      onHorizontalDragCancel: () => setState(() => _artDragX = 0),
                      child: AnimatedScale(
                        scale: player.isPlaying ? 1.0 : 0.92,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutBack,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          transform: Matrix4.translationValues(_artDragX * 0.65, 0, 0),
                          child: Hero(
                            tag: 'aura_current_artwork',
                            child: Builder(
                              builder: (context) {
                                final screenSize = MediaQuery.sizeOf(context);
                                final widthCap = screenSize.width - 64;
                                final heightCap = screenSize.height * 0.39;
                                final rawSide =
                                    widthCap < heightCap ? widthCap : heightCap;
                                final maxSide = rawSide.clamp(120.0, 380.0);
                                return ArtworkView(
                                  artworkPath: track.artworkPath,
                                  seed: '${track.album}_${track.title}',
                                  size: maxSide,
                                  borderRadius: 28,
                                  showShadow: true,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Título, artista y botón de favorito
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: AuraColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${track.artist} · ${track.album}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AuraColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            library.toggleFavorite(track.id);
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: track.isFavorite
                                ? AuraColors.accentSoft
                                : AuraColors.surface,
                          ),
                          icon: Icon(
                            track.isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: track.isFavorite
                                ? AuraColors.accent
                                : AuraColors.textPrimary,
                          ),
                          tooltip: 'Favorito',
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Barra de progreso interactiva táctil
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                        activeTrackColor: AuraColors.accent,
                        inactiveTrackColor: AuraColors.border,
                        thumbColor: AuraColors.accent,
                        overlayColor: AuraColors.accent.withValues(alpha: 0.16),
                      ),
                      child: Slider(
                        min: 0,
                        max: totalMs.toDouble(),
                        value: currentMs.toDouble(),
                        onChangeStart: (_) => player.beginScrub(),
                        onChanged: (val) => player.updateScrub(
                          Duration(milliseconds: val.round()),
                        ),
                        onChangeEnd: (val) => player.endScrub(
                          Duration(milliseconds: val.round()),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            formatDuration(Duration(milliseconds: currentMs)),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AuraColors.textSecondary,
                            ),
                          ),
                          Text(
                            formatDuration(Duration(milliseconds: totalMs)),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AuraColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Controles principales de reproducción
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            player.toggleShuffle();
                          },
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: player.shuffleEnabled
                                ? AuraColors.accent
                                : AuraColors.textSecondary,
                          ),
                          tooltip: 'Aleatorio',
                        ),
                        IconButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            player.skipPrevious();
                          },
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            size: 38,
                            color: AuraColors.textPrimary,
                          ),
                          tooltip: 'Anterior',
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            player.togglePlayPause();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AuraColors.accent,
                              borderRadius: BorderRadius.circular(
                                player.isPlaying ? 24 : 36,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AuraColors.accent.withValues(alpha: 0.34),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            player.skipNext();
                          },
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            size: 38,
                            color: AuraColors.textPrimary,
                          ),
                          tooltip: 'Siguiente',
                        ),
                        IconButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            player.cycleAuraRepeatMode();
                          },
                          icon: Icon(
                            player.repeatMode == AuraRepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            color: player.repeatMode != AuraRepeatMode.off
                                ? AuraColors.accent
                                : AuraColors.textSecondary,
                          ),
                          tooltip: 'Repetir',
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Barra inferior: insignia técnica ExoPlayer + Cola
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: track.isLossless
                                    ? AuraColors.sageSoft
                                    : AuraColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AuraColors.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 15,
                                    color: track.isLossless
                                        ? AuraColors.sage
                                        : AuraColors.textPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${track.technicalSummary} · ExoPlayer',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: track.isLossless
                                            ? AuraColors.sage
                                            : AuraColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          TextButton.icon(
                            onPressed: () => showQueueSheet(context),
                            style: TextButton.styleFrom(
                              foregroundColor: AuraColors.textPrimary,
                              backgroundColor: AuraColors.surface,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.queue_music_rounded, size: 18),
                            label: Text(
                              'Cola (${player.queue.length})',
                              maxLines: 1,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
