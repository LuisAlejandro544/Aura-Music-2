// =============================================================================
// explore_provider.dart — Estado modular de Explorar y streaming con yt-dlp
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Administra la experiencia de descubrimiento tipo streaming en Aura Music:
//   - Categorías curadas por género/estado de ánimo (consultadas bajo demanda
//     con `yt-dlp` sin descargar todo por adelantado).
//   - Búsqueda online por texto o URL de playlist pública, con historial de
//     búsquedas recientes guardado localmente en SharedPreferences.
//   - Resolución progresiva del flujo directo (`resolveExploreStream`) antes de
//     enviar la cola a ExoPlayer (`SimpleCache` + `ResolvingDataSource`) para
//     reproducir mientras se descarga en caché.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/audio/audio_engine_port.dart';
import '../core/models/audio_track.dart';

class ExploreProvider extends ChangeNotifier {
  ExploreProvider({required AudioEnginePort engine}) : _engine = engine;

  static const String _prefRecentQueries = 'aura_explore_recent_queries';

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

  List<ExploreTrackItem> _items = const [];
  List<String> _recentQueries = const [];
  StreamCacheStats _cacheStats = const StreamCacheStats();

  String _activeCategoryId = categories.first.id;
  String _activeQuery = '';
  bool _hasInitializedOnce = false;
  bool _isSearching = false;
  String? _resolvingVideoId;
  String? _errorMessage;
  String? _rawError;
  int _searchSeq = 0;

  List<ExploreTrackItem> get items => _items;
  List<String> get recentQueries => _recentQueries;
  StreamCacheStats get cacheStats => _cacheStats;
  String get activeCategoryId => _activeCategoryId;
  String get activeQuery => _activeQuery;
  bool get hasInitializedOnce => _hasInitializedOnce;
  bool get isSearching => _isSearching;
  String? get resolvingVideoId => _resolvingVideoId;
  String? get errorMessage => _errorMessage;
  String? get rawError => _rawError;

  Future<void> ensureInitialDiscoveryLoaded() async {
    await _loadHistoryAndCache();
    if (_hasInitializedOnce || _isSearching) return;
    _hasInitializedOnce = true;
    await selectCategory(categories.first);
  }

  Future<void> _loadHistoryAndCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefRecentQueries) ?? const [];
      _recentQueries = List<String>.from(saved);
    } catch (_) {}
    try {
      _cacheStats = await _engine.getStreamCacheStats();
    } catch (_) {}
    notifyListeners();
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
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectCategory(ExploreCategory category) async {
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

      _items = _items.map((item) {
        if (item.videoId != target.videoId) return item;
        return item.copyWith(
          cachedBytes: resolved.cachedBytes,
          resolvedMimeType: resolved.mimeType,
          resolvedBitrateKbps: resolved.abr,
          resolvedSampleRateHz: resolved.asr,
          durationMs: resolved.durationMs > 0 ? resolved.durationMs : item.durationMs,
        );
      }).toList(growable: false);

      final sourceItems = contextList ?? _items;
      final queue = sourceItems.map((item) {
        if (item.videoId == target.videoId) {
          return item
              .copyWith(
                cachedBytes: resolved.cachedBytes,
                resolvedMimeType: resolved.mimeType,
                resolvedBitrateKbps: resolved.abr,
                resolvedSampleRateHz: resolved.asr,
                durationMs:
                    resolved.durationMs > 0 ? resolved.durationMs : item.durationMs,
              )
              .toStreamTrack();
        }
        return item.toStreamTrack();
      }).toList(growable: false);

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
