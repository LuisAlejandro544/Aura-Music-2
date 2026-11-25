// =============================================================================
// library_screen.dart — Pantalla de Tu Biblioteca Local
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Organiza las pistas importadas en 4 sub-vistas separadas (Canciones,
//   Álbumes, Carpetas y Playlists locales), con botones dedicados para importar
//   más audio, ordenar el catálogo y crear nuevas playlists locales.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/artwork_view.dart';
import '../../widgets/sheets/import_source_sheet.dart';
import '../../widgets/sheets/track_options_sheet.dart';
import '../../widgets/track_tile.dart';
import '../collection/collection_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.initialSubTab = 0,
  });

  final int initialSubTab;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialSubTab;
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSubTab != widget.initialSubTab) {
      _selectedTab = widget.initialSubTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
            child: Row(
              children: [
                const Text(
                  'Tu Biblioteca',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                    color: AuraColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _showCreatePlaylistDialog(context),
                  icon: const Icon(Icons.playlist_add_rounded),
                  tooltip: 'Nueva playlist',
                ),
                PopupMenuButton<LibrarySortBy>(
                  initialValue: library.sortBy,
                  icon: const Icon(Icons.sort_rounded),
                  tooltip: 'Ordenar canciones',
                  onSelected: library.setSortBy,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: LibrarySortBy.recent,
                      child: Text('Recién importadas'),
                    ),
                    PopupMenuItem(
                      value: LibrarySortBy.title,
                      child: Text('Por título (A-Z)'),
                    ),
                    PopupMenuItem(
                      value: LibrarySortBy.artist,
                      child: Text('Por artista'),
                    ),
                    PopupMenuItem(
                      value: LibrarySortBy.duration,
                      child: Text('Por duración'),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: () => showImportSourceSheet(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AuraColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Importar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),

          // Selector de sub-apartado
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _SegmentTab(
                  label: 'Canciones (${library.tracks.length})',
                  selected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
                const SizedBox(width: 8),
                _SegmentTab(
                  label: 'Álbumes (${library.albums.length})',
                  selected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
                const SizedBox(width: 8),
                _SegmentTab(
                  label: 'Carpetas (${library.folders.length})',
                  selected: _selectedTab == 2,
                  onTap: () => setState(() => _selectedTab = 2),
                ),
                const SizedBox(width: 8),
                _SegmentTab(
                  label: 'Playlists (${library.playlists.length})',
                  selected: _selectedTab == 3,
                  onTap: () => setState(() => _selectedTab = 3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: switch (_selectedTab) {
              0 => _TracksTab(library: library, player: player),
              1 => _CollectionsTab(
                  collections: library.albums,
                  emptyText: 'Importa canciones para ver sus álbumes aquí.',
                ),
              2 => _CollectionsTab(
                  collections: library.folders,
                  emptyText: 'Importa una carpeta de música para verla aquí.',
                ),
              _ => _CollectionsTab(
                  collections: library.playlists,
                  emptyText: 'Crea una playlist local con el botón superior.',
                ),
            },
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuraColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Nueva playlist local',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej: Camino al trabajo, Lossless...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              await context.read<LibraryProvider>().createPlaylist(name);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AuraColors.accent),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AuraColors.textPrimary : AuraColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AuraColors.textPrimary : AuraColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AuraColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _TracksTab extends StatelessWidget {
  const _TracksTab({required this.library, required this.player});

  final LibraryProvider library;
  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    final tracks = library.tracks;
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.music_off_rounded,
                size: 48,
                color: AuraColors.textSecondary,
              ),
              const SizedBox(height: 10),
              const Text(
                'Aún no has importado canciones.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AuraColors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => showImportSourceSheet(context),
                style: FilledButton.styleFrom(backgroundColor: AuraColors.accent),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Importar ahora'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 150),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isActive = player.currentTrack?.id == track.id;
        return TrackTile(
          track: track,
          isActive: isActive,
          isPlaying: isActive && player.isPlaying,
          onTap: () => player.playQueue(tracks, startIndex: index),
          onMoreTap: () => showTrackOptionsSheet(context, track),
        );
      },
    );
  }
}

class _CollectionsTab extends StatelessWidget {
  const _CollectionsTab({
    required this.collections,
    required this.emptyText,
  });

  final List<LocalCollection> collections;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AuraColors.textSecondary, fontSize: 15),
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 150),
      itemCount: collections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final col = collections[index];
        return Material(
          color: AuraColors.surfaceElevated,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CollectionDetailScreen(collection: col),
                ),
              );
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AuraColors.border),
              ),
              child: Row(
                children: [
                  ArtworkView(
                    artworkPath: col.artworkPath,
                    seed: col.title,
                    size: 60,
                    borderRadius: 14,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          col.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AuraColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${col.subtitle} · ${formatCollectionSummary(col.tracks.length, col.totalDuration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AuraColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AuraColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
