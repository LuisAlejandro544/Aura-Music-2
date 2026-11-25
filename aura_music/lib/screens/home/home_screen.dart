// =============================================================================
// home_screen.dart — Pantalla de Inicio de Aura Music
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Presenta la pantalla principal inspirada en servicios de streaming modernos
//   adaptada 100% a música local importada:
//   - Encabezado cálido con botón directo para importar música o explorar cola.
//   - Cuadrícula 2x2 de accesos rápidos (Favoritos, Recientes, Carpetas, Álbumes).
//   - Carrusel horizontal "Recién importado" con carátulas táctiles.
//   - Sección de álbumes/carpetas locales que navegan a CollectionDetailScreen.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/artwork_view.dart';
import '../../widgets/sheets/import_source_sheet.dart';
import '../../widgets/sheets/track_options_sheet.dart';
import '../../widgets/track_tile.dart';
import '../collection/collection_detail_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onNavigateToLibraryTab,
  });

  final void Function(int subTabIndex) onNavigateToLibraryTab;

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final tracks = library.tracks;
    final recentImported = library.recentlyImportedTracks;
    final recentPlayed = library.recentPlayedTracks;
    final albums = library.albums;
    final folders = library.folders;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greetingText(),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tracks.isEmpty
                              ? 'Tu espacio sonoro local en Aura Music'
                              : '${tracks.length} canciones locales listas para sonar',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Configuración',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: c.surface,
                      foregroundColor: c.textPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: c.border),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 20),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => showImportSourceSheet(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Importar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (tracks.isEmpty && library.isHydrated)
            SliverToBoxAdapter(
              child: _EmptyWelcomeCard(
                onImportPressed: () => showImportSourceSheet(context),
              ).animate().fadeIn(duration: 320.ms).slideY(begin: 0.05, end: 0),
            )
          else ...[
            // Cuadrícula rápida 2x2 estilo reproductor moderno
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.45,
                children: [
                  _QuickAccessCard(
                    icon: Icons.favorite_rounded,
                    iconBg: c.accentSoft,
                    iconColor: c.accent,
                    title: 'Favoritos',
                    subtitle: '${library.favoriteTracks.length} pistas',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CollectionDetailScreen(
                            collection: LocalCollection(
                              id: 'special_favorites',
                              title: 'Tus Favoritos',
                              subtitle: 'Selección personal',
                              type: CollectionType.playlist,
                              tracks: library.favoriteTracks,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  _QuickAccessCard(
                    icon: Icons.shuffle_rounded,
                    iconBg: c.amberSoft,
                    iconColor: c.amber,
                    title: 'Modo Mix',
                    subtitle: 'Todo tu catálogo',
                    onTap: () async {
                      if (tracks.isEmpty) return;
                      await player.playQueue(tracks, startIndex: 0);
                      if (!player.shuffleEnabled) {
                        await player.toggleShuffle();
                      }
                    },
                  ),
                  _QuickAccessCard(
                    icon: Icons.folder_rounded,
                    iconBg: c.sageSoft,
                    iconColor: c.sage,
                    title: 'Carpetas',
                    subtitle: '${folders.length} importadas',
                    onTap: () => onNavigateToLibraryTab(2),
                  ),
                  _QuickAccessCard(
                    icon: Icons.album_rounded,
                    iconBg: c.surface,
                    iconColor: c.textPrimary,
                    title: 'Álbumes',
                    subtitle: '${albums.length} colecciones',
                    onTap: () => onNavigateToLibraryTab(1),
                  ),
                ],
              ),
            ),

            // Carrusel horizontal de recién importado
            if (recentImported.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text(
                    'Recién importado',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 212,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: recentImported.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final track = recentImported[index];
                      return _CarouselTrackCard(
                        track: track,
                        onTap: () => player.playQueue(
                          recentImported,
                          startIndex: index,
                        ),
                        onLongPress: () => showTrackOptionsSheet(context, track),
                      );
                    },
                  ),
                ),
              ),
            ],

            // Colecciones por álbum
            if (albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                  child: Row(
                    children: [
                      Text(
                        'Álbumes locales',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: c.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => onNavigateToLibraryTab(1),
                        child: const Text('Ver todos'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 204,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: albums.length.clamp(0, 10),
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return _CollectionCard(
                        collection: album,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  CollectionDetailScreen(collection: album),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],

            // Escuchado recientemente
            if (recentPlayed.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    'Escuchado recientemente',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverList.builder(
                  itemCount: recentPlayed.length,
                  itemBuilder: (context, index) {
                    final track = recentPlayed[index];
                    final isActive = player.currentTrack?.id == track.id;
                    return TrackTile(
                      track: track,
                      isActive: isActive,
                      isPlaying: isActive && player.isPlaying,
                      onTap: () =>
                          player.playQueue(recentPlayed, startIndex: index),
                      onMoreTap: () => showTrackOptionsSheet(context, track),
                    );
                  },
                ),
              ),
            ],
          ],

          // Espacio inferior para MiniPlayer + BottomNav
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ],
      ),
    );
  }
}

class _EmptyWelcomeCard extends StatelessWidget {
  const _EmptyWelcomeCard({required this.onImportPressed});

  final VoidCallback onImportPressed;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.surfaceElevated, c.surface],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.library_music_rounded,
              color: c.accent,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Tu música, bajo tu control',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aura Music no rastrea ni escanea tu almacenamiento. Importa tus archivos MP3, FLAC, WAV o carpetas favoritas para reproducir con ExoPlayer.',
            style: TextStyle(
              fontSize: 14.5,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onImportPressed,
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text(
                'Importar canciones o carpeta',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return Material(
      color: c.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarouselTrackCard extends StatelessWidget {
  const _CarouselTrackCard({
    required this.track,
    required this.onTap,
    required this.onLongPress,
  });

  final AudioTrack track;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 142,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtworkView(
              artworkPath: track.artworkPath,
              seed: '${track.album}_${track.title}',
              size: 142,
              borderRadius: 20,
              showShadow: true,
            ),
            const SizedBox(height: 9),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
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
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.collection,
    required this.onTap,
  });

  final LocalCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 138,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArtworkView(
              artworkPath: collection.artworkPath,
              seed: collection.title,
              size: 138,
              borderRadius: 20,
              showShadow: true,
            ),
            const SizedBox(height: 8),
            Text(
              collection.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            Text(
              '${collection.tracks.length} canciones',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
