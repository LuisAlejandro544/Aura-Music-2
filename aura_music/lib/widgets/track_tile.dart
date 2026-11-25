// =============================================================================
// track_tile.dart — Fila interactiva de canción local
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Representa cada canción en listas, álbumes, carpetas y búsqueda. Muestra
//   carátula, indicador visual animado cuando es la pista activa, insignia de
//   formato (FLAC/MP3/AAC), duración y botón de opciones (abre popup).
// =============================================================================

import 'package:flutter/material.dart';
import '../core/models/audio_track.dart';
import '../core/theme/aura_theme.dart';
import '../core/utils/duration_format.dart';
import 'artwork_view.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.isActive,
    required this.isPlaying,
    required this.onTap,
    required this.onMoreTap,
    this.indexNumber,
  });

  final AudioTrack track;
  final bool isActive;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;
  final int? indexNumber;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Material(
      color: isActive ? c.accentSoft.withValues(alpha: 0.65) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              if (indexNumber != null) ...[
                SizedBox(
                  width: 26,
                  child: Text(
                    '$indexNumber',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isActive ? c.accent : c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Stack(
                alignment: Alignment.center,
                children: [
                  ArtworkView(
                    artworkPath: track.artworkPath,
                    seed: '${track.album}_${track.title}',
                    size: 52,
                    borderRadius: 13,
                  ),
                  if (isActive)
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: c.scrim,
                      ),
                      child: Icon(
                        isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                        color: isActive ? c.accent : c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: track.isLossless ? c.sageSoft : c.surface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            track.formatBadge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: track.isLossless ? c.sage : c.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${track.artist} · ${formatDuration(track.duration)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (track.isFavorite)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 18,
                    color: c.accent,
                  ),
                ),
              IconButton(
                onPressed: onMoreTap,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: c.textSecondary,
                  size: 20,
                ),
                tooltip: 'Opciones de pista',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
