// =============================================================================
// explore_screen.dart — Pantalla de Explorar, "Para ti" y streaming yt-dlp
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Proporciona descubrimiento musical personalizado sin servidor y streaming
//   bajo demanda usando `yt-dlp` + `SimpleCache` (Media3):
//   - Pestaña por defecto "Para ti": muestra mezcla personalizada desde SQLite
//     ("Para ti", "Porque escuchaste..." y "Descubre parecido a tu biblioteca"),
//     con respaldo instantáneo en caché local (6 h) y actualización manual.
//   - Categorías curadas reordenadas dinámicamente según afinidades del usuario.
//   - Buscador por canción, artista o enlace de playlist pública, con historial
//     reciente editable.
//   - Reproducción en streaming inmediato mientras ExoPlayer cachea en disco,
//     registrando señales implícitas de cola y descarga en Biblioteca.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../core/utils/duration_format.dart';
import '../../state/explore_provider.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/artwork_view.dart';
import '../equalizer/equalizer_screen.dart';
import '../import/download_url_screen.dart';
import '../player/full_player_screen.dart';
import '../spatial/spatial_8d_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.isActive,
  });

  final bool isActive;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showRawError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ExploreProvider>().ensureInitialDiscoveryLoaded();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ExploreProvider>().ensureInitialDiscoveryLoaded();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _submitSearch(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _showRawError = false);
    context.read<ExploreProvider>().search(trimmed);
  }

  bool _isSavedLocally(LibraryProvider library, ExploreTrackItem item) {
    for (final track in library.tracks) {
      if (item.videoId.isNotEmpty && track.uri.contains(item.videoId)) {
        return true;
      }
      if (track.title.toLowerCase() == item.title.toLowerCase() &&
          track.artist.toLowerCase() == item.artist.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  Future<void> _playItem(
    ExploreTrackItem item, {
    List<ExploreTrackItem>? contextList,
  }) async {
    final explore = context.read<ExploreProvider>();
    final player = context.read<PlayerProvider>();
    HapticFeedback.selectionClick();

    final queue = await explore.prepareTrackForStreaming(
      item,
      contextList: contextList,
    );
    if (!mounted || queue == null || queue.isEmpty) return;

    final startIdx = queue.indexWhere((t) => t.id == item.trackId);
    await player.playQueue(queue, startIndex: startIdx >= 0 ? startIdx : 0);
  }

  Future<void> _downloadItemOffline(ExploreTrackItem item) async {
    final library = context.read<LibraryProvider>();
    final explore = context.read<ExploreProvider>();
    if (library.isDownloadingUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ya hay una descarga en curso.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Descargando "${item.title}" para escuchar sin conexión...'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final saved = await library.downloadTrackFromUrl(item.webpageUrl);
    if (!mounted) return;
    if (saved != null) {
      await explore.recordDownloadSignal(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Guardada en Biblioteca: ${saved.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            library.downloadError ?? 'No se pudo descargar la pista.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showItemOptions(
    ExploreTrackItem item,
    bool isSaved, {
    List<ExploreTrackItem>? contextList,
  }) {
    final c = AuraTheme.of(context);
    final player = context.read<PlayerProvider>();
    final explore = context.read<ExploreProvider>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ArtworkView(
                    artworkPath: item.thumbnailUrl,
                    seed: '${item.album}_${item.title}',
                    size: 54,
                    borderRadius: 14,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.artist} · ${formatDuration(item.duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(color: c.border, height: 1),
              const SizedBox(height: 6),
              _ExploreSheetAction(
                icon: Icons.play_arrow_rounded,
                label: 'Reproducir en streaming ahora',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _playItem(item, contextList: contextList);
                },
              ),
              _ExploreSheetAction(
                icon: Icons.playlist_play_rounded,
                label: 'Reproducir siguiente en la cola',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await explore.recordQueueSignal(item);
                  final queue = await explore.prepareTrackForStreaming(
                    item,
                    contextList: [item],
                  );
                  if (queue != null && queue.isNotEmpty) {
                    await player.playNextInQueue(queue.first);
                  }
                },
              ),
              _ExploreSheetAction(
                icon: Icons.queue_music_rounded,
                label: 'Añadir a la cola',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await explore.recordQueueSignal(item);
                  final queue = await explore.prepareTrackForStreaming(
                    item,
                    contextList: [item],
                  );
                  if (queue != null && queue.isNotEmpty) {
                    await player.addToQueueEnd(queue.first);
                  }
                },
              ),
              _ExploreSheetAction(
                icon: isSaved
                    ? Icons.check_circle_rounded
                    : Icons.download_for_offline_rounded,
                color: isSaved ? c.sage : c.accent,
                label: isSaved
                    ? 'Ya guardada en Biblioteca'
                    : 'Descargar para escuchar offline',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  if (!isSaved) {
                    _downloadItemOffline(item);
                  }
                },
              ),
              _ExploreSheetAction(
                icon: Icons.tune_rounded,
                label: 'Elegir formato y descargar (M4A / Opus)',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DownloadUrlScreen(initialUrl: item.webpageUrl),
                    ),
                  );
                },
              ),
              _ExploreSheetAction(
                icon: Icons.surround_sound_rounded,
                label: 'Audio 8D (Motor Rust DSP)',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Spatial8dScreen(),
                    ),
                  );
                },
              ),
              _ExploreSheetAction(
                icon: Icons.graphic_eq_rounded,
                label: 'Ecualizador (Motor Rust DSP)',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EqualizerScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRefresh(ExploreProvider explore) async {
    setState(() => _showRawError = false);
    if (explore.activeQuery.isNotEmpty) {
      await explore.search(explore.activeQuery);
    } else if (explore.isPersonalizedMode) {
      await explore.refreshPersonalizedFeed(force: true);
    } else {
      final cat = explore.orderedCategories.firstWhere(
        (item) => item.id == explore.activeCategoryId,
        orElse: () => explore.orderedCategories.first,
      );
      await explore.selectCategory(cat);
    }
  }

  Widget _buildTrackTile(
    BuildContext context,
    ExploreTrackItem item,
    List<ExploreTrackItem> contextList,
    ExploreProvider explore,
    PlayerProvider player,
    LibraryProvider library,
  ) {
    final currentTrack = player.currentTrack;
    final isActive = currentTrack?.id == item.trackId;
    final isResolving = explore.resolvingVideoId == item.videoId;
    final isSaved = _isSavedLocally(library, item);

    return _ExploreTrackTile(
      item: item,
      isActive: isActive,
      isPlaying: isActive && player.isPlaying,
      isBuffering: isActive && player.isBuffering,
      isResolving: isResolving,
      isSavedLocally: isSaved,
      onTap: () => _playItem(item, contextList: contextList),
      onOpenFullPlayer: isActive
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FullPlayerScreen(),
                ),
              );
            }
          : null,
      onDownloadTap: isSaved ? null : () => _downloadItemOffline(item),
      onMoreTap: () => _showItemOptions(
        item,
        isSaved,
        contextList: contextList,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = AuraTheme.of(context);
    final explore = context.watch<ExploreProvider>();
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final feed = explore.personalizedFeed;
    final showPersonalized =
        explore.isPersonalizedMode && explore.activeQuery.isEmpty;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: c.accent,
        onRefresh: () => _handleRefresh(explore),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Explorar',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Streaming progresivo mientras se cachea',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DownloadUrlScreen(),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: c.surfaceElevated,
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(Icons.link_rounded, size: 18, color: c.accent),
                      label: const Text(
                        'URL',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Barra de búsqueda online
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surfaceElevated,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.border),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    style: TextStyle(color: c.textPrimary),
                    onSubmitted: _submitSearch,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar canciones, artistas o URL...',
                      hintStyle: TextStyle(color: c.textSecondary),
                      prefixIcon: Icon(
                        Icons.travel_explore_rounded,
                        color: c.textSecondary,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchCtrl.text.isNotEmpty)
                            IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                              icon: Icon(
                                Icons.close_rounded,
                                color: c.textSecondary,
                              ),
                              tooltip: 'Limpiar',
                            ),
                          IconButton(
                            onPressed: explore.isSearching
                                ? null
                                : () => _submitSearch(_searchCtrl.text),
                            icon: Icon(
                              Icons.arrow_forward_rounded,
                              color: c.accent,
                            ),
                            tooltip: 'Buscar online',
                          ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),

            // Búsquedas recientes
            if (explore.recentQueries.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: explore.recentQueries.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final q = explore.recentQueries[index];
                        return InputChip(
                          label: Text(
                            q,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                          backgroundColor: c.surface,
                          side: BorderSide(color: c.border),
                          deleteIconColor: c.textSecondary,
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _searchCtrl.text = q;
                            _submitSearch(q);
                          },
                          onDeleted: () => explore.removeRecentQuery(q),
                        );
                      },
                    ),
                  ),
                ),
              ),

            // Carrusel de "Para ti" + categorías ordenadas por gusto
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: 1 + explore.orderedCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        final selected = showPersonalized;
                        final tint = AuraTheme.warmTintForSeed(
                          ExploreProvider.forYouCategoryId,
                          isDark: c.isDark,
                        );
                        return GestureDetector(
                          onTap: () {
                            setState(() => _showRawError = false);
                            explore.selectForYou();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 158,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? c.accentSoft
                                  : Color.lerp(c.surfaceElevated, tint, 0.35),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: selected ? c.accent : c.border,
                                width: selected ? 1.4 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 15,
                                      color: selected ? c.accent : c.textPrimary,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        'Para ti',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: selected
                                              ? c.accent
                                              : c.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  feed.isColdStart
                                      ? 'Tendencias iniciales'
                                      : 'Mix según tus gustos',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final cat = explore.orderedCategories[index - 1];
                      final selected = !showPersonalized &&
                          explore.activeCategoryId == cat.id;
                      final tint =
                          AuraTheme.warmTintForSeed(cat.id, isDark: c.isDark);
                      return GestureDetector(
                        onTap: () {
                          setState(() => _showRawError = false);
                          explore.selectCategory(cat);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 158,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? c.accentSoft
                                : Color.lerp(c.surfaceElevated, tint, 0.35),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected ? c.accent : c.border,
                              width: selected ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cat.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: selected ? c.accent : c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                cat.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.2,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Barra de título principal, refresco y caché
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            showPersonalized
                                ? 'Para ti'
                                : (explore.activeQuery.isNotEmpty
                                    ? 'Resultados: "${explore.activeQuery}"'
                                    : _activeCategoryTitle(
                                        explore.orderedCategories,
                                        explore.activeCategoryId,
                                      )),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: c.textPrimary,
                            ),
                          ),
                          if (showPersonalized)
                            Text(
                              feed.isColdStart
                                  ? 'Escucha o importa música para afinar tu mezcla'
                                  : 'Mezcla local sin servidor',
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
                    if (explore.activeQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TextButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            explore.selectForYou();
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: c.accent,
                          ),
                          child: const Text(
                            'Para ti',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (showPersonalized)
                      IconButton(
                        onPressed: explore.isLoadingPersonalized
                            ? null
                            : () => explore.refreshPersonalizedFeed(force: true),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: c.textSecondary,
                        ),
                        tooltip: 'Actualizar mezcla',
                      ),
                    if (explore.cacheStats.usedBytes > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        child: Text(
                          'Caché ${explore.cacheStats.formattedUsed}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Banner de error con retry y detalle técnico
            if (explore.errorMessage != null && explore.errorMessage!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.errorBg,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.errorBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: 19,
                              color: c.errorText,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                explore.errorMessage!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.errorText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _handleRefresh(explore),
                              style: FilledButton.styleFrom(
                                backgroundColor: c.surfaceElevated,
                                foregroundColor: c.textPrimary,
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text(
                                'Reintentar',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (explore.rawError != null &&
                                explore.rawError!.isNotEmpty)
                              OutlinedButton(
                                onPressed: () => setState(
                                  () => _showRawError = !_showRawError,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.errorText,
                                  side: BorderSide(color: c.errorBorder),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  _showRawError ? 'Ocultar log' : 'Ver detalle',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_showRawError && explore.rawError != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.terminalBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                explore.rawError!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: c.terminalText,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

            if (showPersonalized) ...[
              if (explore.isLoadingPersonalized && feed.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: c.accent),
                          const SizedBox(height: 14),
                          Text(
                            'Preparando tu mezcla con yt-dlp + QuickJS...',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (feed.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 130),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 52,
                            color: c.textSecondary.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Aún no pudimos cargar recomendaciones. Desliza hacia abajo o busca cualquier canción para empezar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                if (feed.forYou.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.builder(
                      itemCount: feed.forYou.length,
                      itemBuilder: (context, index) => _buildTrackTile(
                        context,
                        feed.forYou[index],
                        feed.forYou,
                        explore,
                        player,
                        library,
                      ),
                    ),
                  ),

                if (feed.becauseItems.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Text(
                        feed.becauseLabel.isNotEmpty
                            ? feed.becauseLabel
                            : 'Porque escuchaste música similar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 206,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: feed.becauseItems.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final item = feed.becauseItems[index];
                          final isActive =
                              player.currentTrack?.id == item.trackId;
                          final isResolving =
                              explore.resolvingVideoId == item.videoId;
                          final isSaved = _isSavedLocally(library, item);

                          return _ExploreHorizontalCard(
                            item: item,
                            isActive: isActive,
                            isPlaying: isActive && player.isPlaying,
                            isBuffering: isActive && player.isBuffering,
                            isResolving: isResolving,
                            isSavedLocally: isSaved,
                            onTap: () => _playItem(
                              item,
                              contextList: feed.becauseItems,
                            ),
                            onMoreTap: () => _showItemOptions(
                              item,
                              isSaved,
                              contextList: feed.becauseItems,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                if (feed.discoveryItems.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
                      child: Text(
                        'Descubre parecido a tu biblioteca',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.builder(
                      itemCount: feed.discoveryItems.length,
                      itemBuilder: (context, index) => _buildTrackTile(
                        context,
                        feed.discoveryItems[index],
                        feed.discoveryItems,
                        explore,
                        player,
                        library,
                      ),
                    ),
                  ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 160)),
              ],
            ] else ...[
              if (explore.isSearching && explore.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: c.accent),
                          const SizedBox(height: 14),
                          Text(
                            'Consultando catálogo con yt-dlp + QuickJS...',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (explore.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 130),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.explore_outlined,
                            size: 52,
                            color: c.textSecondary.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Busca cualquier canción, artista o pega una playlist pública para escucharla en streaming mientras se guarda en caché.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 160),
                  sliver: SliverList.builder(
                    itemCount: explore.items.length,
                    itemBuilder: (context, index) => _buildTrackTile(
                      context,
                      explore.items[index],
                      explore.items,
                      explore,
                      player,
                      library,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _activeCategoryTitle(
    List<ExploreCategory> categories,
    String categoryId,
  ) {
    for (final cat in categories) {
      if (cat.id == categoryId) return cat.title;
    }
    return 'Descubrimiento';
  }
}

class _ExploreHorizontalCard extends StatelessWidget {
  const _ExploreHorizontalCard({
    required this.item,
    required this.isActive,
    required this.isPlaying,
    required this.isBuffering,
    required this.isResolving,
    required this.isSavedLocally,
    required this.onTap,
    required this.onMoreTap,
  });

  final ExploreTrackItem item;
  final bool isActive;
  final bool isPlaying;
  final bool isBuffering;
  final bool isResolving;
  final bool isSavedLocally;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onMoreTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 152,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive ? c.accentSoft.withValues(alpha: 0.72) : c.surfaceElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isActive ? c.accent : c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ArtworkView(
                  artworkPath: item.thumbnailUrl,
                  seed: '${item.album}_${item.title}',
                  size: 130,
                  borderRadius: 14,
                ),
                if (isResolving || (isActive && isBuffering))
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                else if (isActive)
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isPlaying
                          ? Icons.equalizer_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: onMoreTap,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.more_horiz_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isActive ? c.accent : c.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isSavedLocally ? 'Guardada · ${item.artist}' : item.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: isSavedLocally ? c.sage : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreTrackTile extends StatelessWidget {
  const _ExploreTrackTile({
    required this.item,
    required this.isActive,
    required this.isPlaying,
    required this.isBuffering,
    required this.isResolving,
    required this.isSavedLocally,
    required this.onTap,
    required this.onMoreTap,
    this.onOpenFullPlayer,
    this.onDownloadTap,
  });

  final ExploreTrackItem item;
  final bool isActive;
  final bool isPlaying;
  final bool isBuffering;
  final bool isResolving;
  final bool isSavedLocally;
  final VoidCallback onTap;
  final VoidCallback? onOpenFullPlayer;
  final VoidCallback? onDownloadTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    final statusLabel = isSavedLocally
        ? 'GUARDADA'
        : (item.hasCachedChunks ? 'CACHÉ' : 'STREAM');
    final statusBg = isSavedLocally
        ? c.sageSoft
        : (item.hasCachedChunks ? c.accentSoft : c.surface);
    final statusColor = isSavedLocally
        ? c.sage
        : (item.hasCachedChunks ? c.accent : c.textSecondary);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? c.accentSoft.withValues(alpha: 0.72) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isActive && onOpenFullPlayer != null ? onOpenFullPlayer : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  ArtworkView(
                    artworkPath: item.thumbnailUrl,
                    seed: '${item.album}_${item.title}',
                    size: 54,
                    borderRadius: 14,
                  ),
                  if (isResolving || (isActive && isBuffering))
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else if (isActive)
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.equalizer_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isActive ? c.accent : c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSavedLocally || item.hasCachedChunks
                                  ? Colors.transparent
                                  : c.border,
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${item.artist}${item.durationMs > 0 ? " · ${formatDuration(item.duration)}" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDownloadTap,
                icon: Icon(
                  isSavedLocally
                      ? Icons.check_circle_rounded
                      : Icons.download_for_offline_outlined,
                  size: 21,
                  color: isSavedLocally ? c.sage : c.textSecondary,
                ),
                tooltip: isSavedLocally
                    ? 'Guardada en Biblioteca'
                    : 'Guardar offline',
              ),
              IconButton(
                onPressed: onMoreTap,
                icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
                tooltip: 'Opciones',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExploreSheetAction extends StatelessWidget {
  const _ExploreSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AuraTheme.of(context);
    return ListTile(
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: color ?? c.textPrimary),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: color ?? c.textPrimary,
        ),
      ),
    );
  }
}
