// =============================================================================
// explore_provider.dart — Estado modular de Explorar, recomendaciones y streaming
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Administra la experiencia de descubrimiento personalizado y streaming en Aura:
//   - Sección "Para ti" sin servidor: combina biblioteca local, señales de
//     streaming (`explore_signals`) y Mixes RD de YouTube vía `yt-dlp`.
//   - Caché local SQLite (6 h) para apertura instantánea de la pestaña y
//     reordenamiento dinámico de categorías según afinidades del usuario.
//   - Búsqueda online por texto o URL de playlist pública, con historial
//     reciente en SharedPreferences.
//   - Resolución progresiva del flujo directo (`resolveExploreStream`) antes de
//     enviar la cola a ExoPlayer (`SimpleCache` + `ResolvingDataSource`).
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/audio/audio_engine_port.dart';
import '../core/models/audio_track.dart';
import '../core/recommendations/taste_profiler.dart';
import '../core/storage/library_database.dart';
import 'library_provider.dart';

class ExploreProvider extends ChangeNotifier {
  ExploreProvider({
    required AudioEnginePort engine,
    required LibraryDatabase database,
    required LibraryProvider library,
  })  : _engine = engine,
        _database = database,
        _library = library;

  static const String _prefRecentQueries = 'aura_explore_recent_queries';
  static const String forYouCategoryId = 'for_you';
  static const Duration _feedCacheTtl = Duration(hours: 6);

  static const List<ExploreCategory> categories = [
    ExploreCategory(
      id: 'hits',
      title: 'Éxitos Globales',
      subtitle: 'Tendencias y audio oficial',
      query: 'top music hits official audio',
    ),
    ExploreCategory(
      id: 'lofi',
      title: 'Lo-Fi & Estudio',
      subtitle: 'Ritmos suaves para concentrarse',
      query: 'lofi hip hop chill study beats',
    ),
    ExploreCategory(
      id: 'latin',
      title: 'Urbano & Latino',
      subtitle: 'Pop latino, urbano y ritmo',
      query: 'latin urban pop music official audio',
    ),
    ExploreCategory(
      id: 'electronic',
      title: 'Electrónica',
      subtitle: 'Synthwave, house y chillout',
      query: 'electronic synthwave chillout music',
    ),
    ExploreCategory(
      id: 'rock',
      title: 'Rock & Indie',
      subtitle: 'Guitarras y clásicos alternativos',
      query: 'indie rock classic hits audio',
    ),
    ExploreCategory(
      id: 'acoustic',
      title: 'Acústico',
      subtitle: 'Sesiones íntimas y folk cálido',
      query: 'acoustic indie folk sessions audio',
    ),
    ExploreCategory(
      id: 'jazz',
      title: 'Jazz Nocturno',
      subtitle: 'Instrumental cálido y saxofón',
      query: 'late night jazz instrumental',
    ),
    ExploreCategory(
      id: 'instrumental',
      title: 'Bandas Sonoras',
      subtitle: 'Ambient, piano y cine',
      query: 'ambient piano soundtrack instrumental',
    ),
  ];

  final AudioEnginePort _engine;
  final LibraryDatabase _database;
  final LibraryProvider _library;

  ExplorePersonalizedFeed _personalizedFeed = const ExplorePersonalizedFeed();
  List<ExploreCategory> _orderedCategories = categories;
  List<ExploreTrackItem> _items = const [];
  List<String> _recentQueries = const [];
  StreamCacheStats _cacheStats = const StreamCacheStats();

  bool _isPersonalizedMode = true;
  String _activeCategoryId = forYouCategoryId;
  String _activeQuery = '';
  bool _hasInitializedOnce = false;
  bool _isLoadingPersonalized = false;
  bool _isSearching = false;
  String? _resolvingVideoId;
  String? _errorMessage;
  String? _rawError;
  int _searchSeq = 0;
  int _personalizedSeq = 0;

  ExplorePersonalizedFeed get personalizedFeed => _personalizedFeed;
  List<ExploreCategory> get orderedCategories => _orderedCategories;
  List<ExploreTrackItem> get items => _items;
  List<String> get recentQueries => _recentQueries;
  StreamCacheStats get cacheStats => _cacheStats;
  bool get isPersonalizedMode => _isPersonalizedMode;
  String get activeCategoryId => _activeCategoryId;
  String get activeQuery => _activeQuery;
  bool get hasInitializedOnce => _hasInitializedOnce;
  bool get isLoadingPersonalized => _isLoadingPersonalized;
  bool get isSearching => _isSearching;
  String? get resolvingVideoId => _resolvingVideoId;
  String? get errorMessage => _errorMessage;
  String? get rawError => _rawError;

  Future<void> ensureInitialDiscoveryLoaded() async {
    final profile = await _hydrateLocalSignalsAndCache();
    if (_hasInitializedOnce || _isLoadingPersonalized || _isSearching) return;
    _hasInitializedOnce = true;

    final needsRefresh = _personalizedFeed.isEmpty ||
        (_personalizedFeed.isColdStart && profile.hasSignals);
    if (needsRefresh) {
      await refreshPersonalizedFeed(force: true);
    }
  }

  Future<TasteProfilePayload> _hydrateLocalSignalsAndCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefRecentQueries) ?? const [];
      _recentQueries = List<String>.from(saved);
    } catch (_) {}

    try {
      _cacheStats = await _engine.getStreamCacheStats();
    } catch (_) {}

    var profile = TasteProfilePayload(
      seedTracks: const [],
      seedArtists: const [],
      recentQueries: _recentQueries,
      excludeVideoIds: const {},
      excludeTitleKeys: const {},
      preferredDurationMs: 210000,
      hasSignals: false,
    );

    try {
      final results = await Future.wait<dynamic>([
        _database.getExploreSignals(),
        _database.getTrackYoutubeSeeds(),
        _database.getCachedExploreFeed(maxAge: _feedCacheTtl),
      ]);
      final signals = results[0] as List<ExploreSignalRecord>;
      final seeds = results[1] as Map<String, String>;
      final cachedFeed = results[2] as ExplorePersonalizedFeed?;

      profile = TasteProfiler.buildProfile(
        localTracks: _library.tracks,
        exploreSignals: signals,
        cachedSeedVideoIds: seeds,
        recentQueries: _recentQueries,
      );
      _orderedCategories = TasteProfiler.rankCategories(categories, profile);

      if (cachedFeed != null && !cachedFeed.isEmpty) {
        _personalizedFeed =
            TasteProfiler.rerankPersonalizedFeed(cachedFeed, profile);
      }
    } catch (_) {}

    notifyListeners();
    return profile;
  }

  Future<void> refreshPersonalizedFeed({bool force = false}) async {
    final seq = ++_personalizedSeq;
    _hasInitializedOnce = true;
    if (force || _personalizedFeed.isEmpty) {
      _isLoadingPersonalized = true;
      _errorMessage = null;
      _rawError = null;
      notifyListeners();
    }

    try {
      final results = await Future.wait<dynamic>([
        _database.getExploreSignals(),
        _database.getTrackYoutubeSeeds(),
      ]);
      if (seq != _personalizedSeq) return;

      final signals = results[0] as List<ExploreSignalRecord>;
      final seeds = results[1] as Map<String, String>;

      final profile = TasteProfiler.buildProfile(
        localTracks: _library.tracks,
        exploreSignals: signals,
        cachedSeedVideoIds: seeds,
        recentQueries: _recentQueries,
      );
      _orderedCategories = TasteProfiler.rankCategories(categories, profile);

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (!profile.hasSignals) {
        final fallback = await _engine.searchExplore(
          query: categories.first.query,
          limit: 16,
        );
        if (seq != _personalizedSeq) return;
        _personalizedFeed = ExplorePersonalizedFeed(
          forYou: fallback.items,
          generatedAtMs: nowMs,
          isColdStart: true,
        );
        _cacheStats = await _engine.getStreamCacheStats();
        return;
      }

      var rawFeed = await _engine.fetchExploreRecommendations(
        tastePayloadJson: profile.toJsonString(),
        limit: 16,
      );
      if (seq != _personalizedSeq) return;

      if (rawFeed.resolvedSeeds.isNotEmpty) {
        await _database.saveTrackYoutubeSeeds(rawFeed.resolvedSeeds);
      }

      var reranked = TasteProfiler.rerankPersonalizedFeed(rawFeed, profile);

      // Si las semillas no arrojaron resultados (p.ej. red o Mix vacío), usa búsqueda del artista top
      if (reranked.forYou.isEmpty) {
        final fallbackQuery = profile.seedArtists.isNotEmpty
            ? '${profile.seedArtists.first.name} official audio'
            : categories.first.query;
        final fallback =
            await _engine.searchExplore(query: fallbackQuery, limit: 16);
        if (seq != _personalizedSeq) return;
        reranked = TasteProfiler.rerankPersonalizedFeed(
          reranked.copyWith(forYou: fallback.items),
          profile,
        );
      }

      _personalizedFeed = reranked.copyWith(
        generatedAtMs: nowMs,
        isColdStart: false,
      );
      if (!_personalizedFeed.isEmpty) {
        await _database.saveCachedExploreFeed(_personalizedFeed);
      }
      _cacheStats = await _engine.getStreamCacheStats();
    } on YtDownloadFailure catch (e) {
      if (seq != _personalizedSeq) return;
      _errorMessage = e.summary;
      _rawError = e.rawLog;
    } catch (e, stack) {
      if (seq != _personalizedSeq) return;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _rawError = '$e\n$stack';
    } finally {
      if (seq == _personalizedSeq) {
        _isLoadingPersonalized = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectForYou() async {
    _isPersonalizedMode = true;
    _activeCategoryId = forYouCategoryId;
    _activeQuery = '';
    _errorMessage = null;
    _rawError = null;
    notifyListeners();

    if (_personalizedFeed.isEmpty || _personalizedFeed.isColdStart) {
      await refreshPersonalizedFeed(force: true);
    }
  }

  Future<void> refreshCacheStats() async {
    try {
      _cacheStats = await _engine.getStreamCacheStats();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> clearStreamCache() async {
    try {
      _cacheStats = await _engine.clearStreamCache();
      _items = _items
          .map((item) => item.copyWith(cachedBytes: 0))
          .toList(growable: false);
      _personalizedFeed = _personalizedFeed.copyWith(
        forYou: _personalizedFeed.forYou
            .map((item) => item.copyWith(cachedBytes: 0))
            .toList(growable: false),
        becauseItems: _personalizedFeed.becauseItems
            .map((item) => item.copyWith(cachedBytes: 0))
            .toList(growable: false),
        discoveryItems: _personalizedFeed.discoveryItems
            .map((item) => item.copyWith(cachedBytes: 0))
            .toList(growable: false),
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectCategory(ExploreCategory category) async {
    _isPersonalizedMode = false;
    _activeCategoryId = category.id;
    await _runSearch(
      query: category.query,
      recordHistory: false,
      displayQuery: '',
    );
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _isPersonalizedMode = false;
    _activeCategoryId = '';
    await _runSearch(
      query: trimmed,
      recordHistory: true,
      displayQuery: trimmed,
    );
  }

  Future<void> _runSearch({
    required String query,
    required bool recordHistory,
    required String displayQuery,
  }) async {
    final seq = ++_searchSeq;
    _hasInitializedOnce = true;
    _isSearching = true;
    _activeQuery = displayQuery;
    _errorMessage = null;
    _rawError = null;
    notifyListeners();

    if (recordHistory) {
      await _saveRecentQuery(query);
    }

    try {
      final result = await _engine.searchExplore(query: query, limit: 18);
      if (seq != _searchSeq) return;
      _items = result.items;
      _cacheStats = await _engine.getStreamCacheStats();
    } on YtDownloadFailure catch (e) {
      if (seq != _searchSeq) return;
      _errorMessage = e.summary;
      _rawError = e.rawLog;
    } catch (e, stack) {
      if (seq != _searchSeq) return;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _rawError = '$e\n$stack';
    } finally {
      if (seq == _searchSeq) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  ExploreTrackItem _applyResolvedMetadata(
    ExploreTrackItem item,
    String targetVideoId,
    ResolvedStreamInfo resolved,
  ) {
    if (item.videoId != targetVideoId) return item;
    return item.copyWith(
      cachedBytes: resolved.cachedBytes,
      resolvedMimeType: resolved.mimeType,
      resolvedBitrateKbps: resolved.abr,
      resolvedSampleRateHz: resolved.asr,
      durationMs: resolved.durationMs > 0 ? resolved.durationMs : item.durationMs,
    );
  }

  /// Pre-resuelve la pista tocada en streaming y actualiza la lista para que
  /// ExoPlayer comience a reproducir de inmediato mientras cachea en disco.
  Future<List<AudioTrack>?> prepareTrackForStreaming(
    ExploreTrackItem target, {
    List<ExploreTrackItem>? contextList,
  }) async {
    if (_resolvingVideoId != null) return null;
    _resolvingVideoId = target.videoId;
    _errorMessage = null;
    _rawError = null;
    notifyListeners();

    try {
      final resolved = await _engine.resolveExploreStream(
        url: target.webpageUrl,
        videoId: target.videoId,
      );

      _items = _items
          .map((item) => _applyResolvedMetadata(item, target.videoId, resolved))
          .toList(growable: false);

      _personalizedFeed = _personalizedFeed.copyWith(
        forYou: _personalizedFeed.forYou
            .map((item) => _applyResolvedMetadata(item, target.videoId, resolved))
            .toList(growable: false),
        becauseItems: _personalizedFeed.becauseItems
            .map((item) => _applyResolvedMetadata(item, target.videoId, resolved))
            .toList(growable: false),
        discoveryItems: _personalizedFeed.discoveryItems
            .map((item) => _applyResolvedMetadata(item, target.videoId, resolved))
            .toList(growable: false),
      );

      final sourceItems = contextList ??
          (_isPersonalizedMode && _activeQuery.isEmpty
              ? _personalizedFeed.forYou
              : _items);
      final queue = sourceItems
          .map(
            (item) => _applyResolvedMetadata(item, target.videoId, resolved)
                .toStreamTrack(),
          )
          .toList(growable: false);

      _cacheStats = await _engine.getStreamCacheStats();
      return queue;
    } on YtDownloadFailure catch (e) {
      _errorMessage = e.summary;
      _rawError = e.rawLog;
      return null;
    } catch (e, stack) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _rawError = '$e\n$stack';
      return null;
    } finally {
      _resolvingVideoId = null;
      notifyListeners();
    }
  }

  Future<void> handleStreamSignal(
    AudioTrack track, {
    bool played = false,
    bool completed = false,
    bool skippedEarly = false,
  }) async {
    final vid = track.streamVideoId;
    if (vid.isEmpty) return;
    try {
      await _database.recordExploreSignal(
        videoId: vid,
        title: track.title,
        artist: track.artist,
        webpageUrl: track.effectiveSourceUrl,
        thumbnailUrl: track.artworkPath ?? '',
        durationMs: track.durationMs,
        played: played,
        completed: completed,
        skippedEarly: skippedEarly,
      );
      await _recomputeLocalOrderAndFilters();
    } catch (_) {}
  }

  Future<void> recordQueueSignal(ExploreTrackItem item) async {
    try {
      await _database.recordExploreSignal(
        videoId: item.videoId,
        title: item.title,
        artist: item.artist,
        webpageUrl: item.webpageUrl,
        thumbnailUrl: item.thumbnailUrl,
        durationMs: item.durationMs,
        queued: true,
      );
      await _recomputeLocalOrderAndFilters();
    } catch (_) {}
  }

  Future<void> recordDownloadSignal(ExploreTrackItem item) async {
    try {
      await _database.recordExploreSignal(
        videoId: item.videoId,
        title: item.title,
        artist: item.artist,
        webpageUrl: item.webpageUrl,
        thumbnailUrl: item.thumbnailUrl,
        durationMs: item.durationMs,
        downloaded: true,
      );
      await _recomputeLocalOrderAndFilters();
    } catch (_) {}
  }

  Future<void> _recomputeLocalOrderAndFilters() async {
    final signals = await _database.getExploreSignals();
    final seeds = await _database.getTrackYoutubeSeeds();
    final profile = TasteProfiler.buildProfile(
      localTracks: _library.tracks,
      exploreSignals: signals,
      cachedSeedVideoIds: seeds,
      recentQueries: _recentQueries,
    );
    _orderedCategories = TasteProfiler.rankCategories(categories, profile);
    if (!_personalizedFeed.isEmpty) {
      _personalizedFeed =
          TasteProfiler.rerankPersonalizedFeed(_personalizedFeed, profile);
    }
    notifyListeners();
  }

  Future<void> _saveRecentQuery(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return;
    final next = [
      cleaned,
      ..._recentQueries.where((q) => q.toLowerCase() != cleaned.toLowerCase()),
    ].take(8).toList(growable: false);
    _recentQueries = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefRecentQueries, next);
      await _recomputeLocalOrderAndFilters();
    } catch (_) {}
  }

  Future<void> removeRecentQuery(String query) async {
    _recentQueries =
        _recentQueries.where((q) => q != query).toList(growable: false);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefRecentQueries, _recentQueries);
    } catch (_) {}
  }
}
