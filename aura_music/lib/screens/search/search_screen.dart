// =============================================================================
// search_screen.dart — Pantalla dedicada de búsqueda instantánea local
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Permite filtrar al instante entre todas las canciones importadas por título,
//   artista, álbum o carpeta de origen, con chips de filtro rápido (Todo,
//   Lossless, Favoritos).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/sheets/track_options_sheet.dart';
import '../../widgets/track_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _filter = 'all';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final results = library.search(_query, filter: _filter);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Text(
              'Buscar',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
                color: c.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: c.surfaceElevated,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.border),
              ),
              child: TextField(
                controller: _controller,
                style: TextStyle(color: c.textPrimary),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Canción, artista, álbum o carpeta...',
                  hintStyle: TextStyle(color: c.textSecondary),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: c.textSecondary,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(Icons.close_rounded, color: c.textSecondary),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _FilterChipItem(
                  label: 'Todo',
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChipItem(
                  label: 'Lossless (FLAC / WAV)',
                  selected: _filter == 'lossless',
                  onTap: () => setState(() => _filter = 'lossless'),
                ),
                const SizedBox(width: 8),
                _FilterChipItem(
                  label: 'Favoritos',
                  selected: _filter == 'favorites',
                  onTap: () => setState(() => _filter = 'favorites'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.manage_search_rounded,
                            size: 52,
                            color: c.textSecondary.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            library.tracks.isEmpty
                                ? 'Importa canciones primero para buscarlas aquí.'
                                : 'Sin coincidencias para "$_query"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 150),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final track = results[index];
                      final isActive = player.currentTrack?.id == track.id;
                      return TrackTile(
                        track: track,
                        isActive: isActive,
                        isPlaying: isActive && player.isPlaying,
                        onTap: () => player.playQueue(results, startIndex: index),
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

class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? c.accent : c.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : c.textPrimary,
          ),
        ),
      ),
    );
  }
}
