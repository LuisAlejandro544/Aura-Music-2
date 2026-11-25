// =============================================================================
// collection_detail_screen.dart — Pantalla de detalle de Álbum/Carpeta/Playlist
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Muestra una pantalla separada para explorar una colección local con
//   cabecera amplia de carátula, resumen de duración, botones Reproducir todo /
//   Aleatorio y listado numerado de canciones.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../state/player_provider.dart';
import '../../widgets/artwork_view.dart';
import '../../widgets/sheets/track_options_sheet.dart';
import '../../widgets/track_tile.dart';

class CollectionDetailScreen extends StatelessWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collection,
  });

  final LocalCollection collection;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final tint = AuraTheme.warmTintForSeed(collection.title);

    return Scaffold(
      backgroundColor: AuraColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 284,
            pinned: true,
            backgroundColor: AuraColors.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tint.withValues(alpha: 0.75),
                      AuraColors.background,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 18),
                      ArtworkView(
                        artworkPath: collection.artworkPath,
                        seed: collection.title,
                        size: 146,
                        borderRadius: 24,
                        showShadow: true,
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          collection.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AuraColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          '${collection.subtitle} · ${formatCollectionSummary(collection.tracks.length, collection.totalDuration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AuraColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: collection.tracks.isEmpty
                          ? null
                          : () => player.playQueue(collection.tracks, startIndex: 0),
                      style: FilledButton.styleFrom(
                        backgroundColor: AuraColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text(
                        'Reproducir',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: collection.tracks.isEmpty
                          ? null
                          : () async {
                              await player.playQueue(
                                collection.tracks,
                                startIndex: 0,
                              );
                              if (!player.shuffleEnabled) {
                                await player.toggleShuffle();
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AuraColors.textPrimary,
                        side: const BorderSide(color: AuraColors.border),
                        backgroundColor: AuraColors.surfaceElevated,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text(
                        'Aleatorio',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (collection.tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Esta colección está vacía.',
                  style: TextStyle(color: AuraColors.textSecondary),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 60),
              sliver: SliverList.builder(
                itemCount: collection.tracks.length,
                itemBuilder: (context, index) {
                  final track = collection.tracks[index];
                  final isActive = player.currentTrack?.id == track.id;
                  return TrackTile(
                    track: track,
                    indexNumber: index + 1,
                    isActive: isActive,
                    isPlaying: isActive && player.isPlaying,
                    onTap: () =>
                        player.playQueue(collection.tracks, startIndex: index),
                    onMoreTap: () => showTrackOptionsSheet(context, track),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
