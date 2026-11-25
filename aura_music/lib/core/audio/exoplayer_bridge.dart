// =============================================================================
// exoplayer_bridge.dart — Implementación concreta con Media3 ExoPlayer nativo
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Implementa AudioEnginePort comunicándose con AuraAudioBridge.kt mediante
//   MethodChannel y EventChannel. Todas las operaciones pesadas (SAF, lectura
//   de etiquetas y decodificación) se ejecutan fuera del hilo UI de Flutter.
// =============================================================================

import 'dart:async';
import 'package:flutter/services.dart';
import '../models/audio_track.dart';
import 'audio_engine_port.dart';

class ExoPlayerBridge implements AudioEnginePort {
  static const MethodChannel _methodChannel =
      MethodChannel('com.auramusic.player/audio');
  static const EventChannel _eventChannel =
      EventChannel('com.auramusic.player/events');

  final StreamController<NativePlaybackEvent> _playbackController =
      StreamController<NativePlaybackEvent>.broadcast();
  final StreamController<({int processed, int total})> _importController =
      StreamController<({int processed, int total})>.broadcast();
  final StreamController<DownloadProgressEvent> _downloadProgressController =
      StreamController<DownloadProgressEvent>.broadcast();
  final StreamController<YtUpdateProgressEvent> _ytUpdateProgressController =
      StreamController<YtUpdateProgressEvent>.broadcast();
  final StreamController<Spatial8dState> _spatial8dController =
      StreamController<Spatial8dState>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;

  @override
  AudioEngineBackend get activeBackend => AudioEngineBackend.exoPlayer;

  @override
  Stream<NativePlaybackEvent> get playbackEvents => _playbackController.stream;

  @override
  Stream<({int processed, int total})> get importProgressEvents =>
      _importController.stream;

  @override
  Stream<DownloadProgressEvent> get downloadProgressEvents =>
      _downloadProgressController.stream;

  @override
  Stream<YtUpdateProgressEvent> get ytUpdateProgressEvents =>
      _ytUpdateProgressController.stream;

  @override
  Stream<Spatial8dState> get spatial8dEvents => _spatial8dController.stream;

  @override
  Stream<String> get errorEvents => _errorController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object err) {
        _errorController.add('Error de canal nativo: $err');
      },
    );

    try {
      await _methodChannel.invokeMethod<dynamic>('initEngine');
    } on MissingPluginException {
      // Permite probar la interfaz en desktop/test sin romper el arranque.
    }
  }

  void _handleNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final type = map['type'] as String?;

    switch (type) {
      case 'playbackState':
        final repeatStr = (map['repeatMode'] as String?) ?? 'off';
        final repeatMode = switch (repeatStr) {
          'all' => AuraRepeatMode.all,
          'one' => AuraRepeatMode.one,
          _ => AuraRepeatMode.off,
        };
        _playbackController.add(
          NativePlaybackEvent(
            isPlaying: map['isPlaying'] == true,
            isBuffering: map['isBuffering'] == true,
            currentIndex: (map['currentIndex'] as num?)?.toInt() ?? 0,
            currentMediaId: map['currentMediaId'] as String?,
            positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
            bufferedPositionMs:
                (map['bufferedPositionMs'] as num?)?.toInt() ?? 0,
            durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
            shuffleEnabled: map['shuffleEnabled'] == true,
            repeatMode: repeatMode,
          ),
        );
      case 'importProgress':
        _importController.add((
          processed: (map['processed'] as num?)?.toInt() ?? 0,
          total: (map['total'] as num?)?.toInt() ?? 0,
        ));
      case 'downloadProgress':
        _downloadProgressController.add(
          DownloadProgressEvent(
            stage: (map['stage'] ?? 'resolving').toString(),
            percent: (map['percent'] as num?)?.toDouble() ?? 0.0,
            downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
            totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
            message: (map['message'] ?? '').toString(),
          ),
        );
      case 'ytUpdateProgress':
        _ytUpdateProgressController.add(
          YtUpdateProgressEvent(
            stage: (map['stage'] ?? 'checking').toString(),
            packageName: (map['packageName'] ?? '').toString(),
            percent: (map['percent'] as num?)?.toDouble() ?? 0.0,
            downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
            totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
            message: (map['message'] ?? '').toString(),
          ),
        );
      case 'spatial8dState':
        _spatial8dController.add(Spatial8dState.fromMap(map));
      case 'error':
        _errorController.add(
          (map['message'] as String?) ?? 'Error desconocido en ExoPlayer',
        );
    }
  }

  @override
  Future<List<AudioTrack>> pickAudioFiles() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawList =
        await _methodChannel.invokeMethod<List<dynamic>>('pickAudioFiles') ??
            const [];
    return rawList
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => AudioTrack.fromMap({
              ...Map<String, dynamic>.from(m),
              'importedAtMs': now,
            }))
        .toList();
  }

  @override
  Future<List<AudioTrack>> pickAudioFolder() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawList =
        await _methodChannel.invokeMethod<List<dynamic>>('pickAudioFolder') ??
            const [];
    return rawList
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => AudioTrack.fromMap({
              ...Map<String, dynamic>.from(m),
              'importedAtMs': now,
            }))
        .toList();
  }

  @override
  Future<AudioTrack> downloadFromUrl({
    required String url,
    YtDownloadFormat format = YtDownloadFormat.best,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'downloadFromUrl',
        {
          'url': url,
          'format': format.name,
        },
      );
      if (raw == null || raw.isEmpty) {
        throw const YtDownloadFailure(
          summary: 'No se recibió respuesta del motor yt-dlp',
          rawLog: 'MethodChannel downloadFromUrl devolvió null o mapa vacío.',
        );
      }
      return AudioTrack.fromMap({
        ...raw,
        'importedAtMs': now,
      });
    } on PlatformException catch (e) {
      final summary = (e.message ?? '').trim().isNotEmpty
          ? e.message!.trim()
          : 'Error al descargar desde URL (${e.code})';
      final rawDetails = (e.details?.toString() ?? '').trim();
      throw YtDownloadFailure(
        summary: summary,
        rawLog: rawDetails.isNotEmpty
            ? rawDetails
            : 'Code: ${e.code}\nMessage: $summary',
      );
    }
  }

  @override
  Future<ExploreSearchResult> searchExplore({
    required String query,
    int limit = 18,
  }) async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'searchExplore',
        {
          'query': query,
          'limit': limit,
        },
      );
      final map = raw ?? const <String, dynamic>{};
      final rawItems = map['items'];
      final items = rawItems is List
          ? rawItems
              .whereType<Map<dynamic, dynamic>>()
              .map((item) => ExploreTrackItem.fromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .where((item) => item.videoId.isNotEmpty)
              .toList()
          : const <ExploreTrackItem>[];
      return ExploreSearchResult(
        query: (map['query'] ?? query).toString(),
        items: items,
      );
    } on PlatformException catch (e) {
      final summary = (e.message ?? '').trim().isNotEmpty
          ? e.message!.trim()
          : 'Error al explorar música (${e.code})';
      final rawDetails = (e.details?.toString() ?? '').trim();
      throw YtDownloadFailure(
        summary: summary,
        rawLog: rawDetails.isNotEmpty
            ? rawDetails
            : 'Code: ${e.code}\nMessage: $summary',
      );
    } on MissingPluginException {
      return ExploreSearchResult(query: query, items: const []);
    }
  }

  @override
  Future<ResolvedStreamInfo> resolveExploreStream({
    required String url,
    String videoId = '',
    YtDownloadFormat format = YtDownloadFormat.best,
  }) async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'resolveExploreStream',
        {
          'url': url,
          'videoId': videoId,
          'format': format.name,
        },
      );
      if (raw == null || raw.isEmpty) {
        throw const YtDownloadFailure(
          summary: 'No se recibió flujo de audio desde yt-dlp',
          rawLog: 'MethodChannel resolveExploreStream devolvió null o vacío.',
        );
      }
      return ResolvedStreamInfo.fromMap(raw);
    } on PlatformException catch (e) {
      final summary = (e.message ?? '').trim().isNotEmpty
          ? e.message!.trim()
          : 'No se pudo conectar el streaming (${e.code})';
      final rawDetails = (e.details?.toString() ?? '').trim();
      throw YtDownloadFailure(
        summary: summary,
        rawLog: rawDetails.isNotEmpty
            ? rawDetails
            : 'Code: ${e.code}\nMessage: $summary',
      );
    }
  }

  @override
  Future<StreamCacheStats> getStreamCacheStats() async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getStreamCacheStats',
      );
      return StreamCacheStats.fromMap(raw ?? const <String, dynamic>{});
    } on MissingPluginException {
      return const StreamCacheStats();
    }
  }

  @override
  Future<StreamCacheStats> clearStreamCache() async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'clearStreamCache',
      );
      return StreamCacheStats.fromMap(raw ?? const <String, dynamic>{});
    } on MissingPluginException {
      return const StreamCacheStats();
    }
  }

  @override
  Future<YtEngineStatus> getYtEngineStatus({bool includePython = false}) async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getYtEngineStatus',
        {'includePython': includePython},
      );
      return YtEngineStatus.fromMap(raw ?? const <String, dynamic>{});
    } on MissingPluginException {
      return const YtEngineStatus(
        pythonStarted: false,
        pythonVersion: '',
        ytDlpVersion: '',
        ejsVersion: '',
        quickjsReady: false,
        rustCrate: '',
        audioProcessor: '',
        arch: '',
      );
    }
  }

  @override
  Future<YtUpdateCheckResult> checkYtEngineUpdates() async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
      'checkYtEngineUpdates',
    );
    return YtUpdateCheckResult.fromMap(raw ?? const <String, dynamic>{});
  }

  @override
  Future<YtUpdateResult> updateYtEngine({bool force = false}) async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
      'updateYtEngine',
      {'force': force},
    );
    return YtUpdateResult.fromMap(raw ?? const <String, dynamic>{});
  }

  @override
  Future<bool> setYtAutoUpdateEnabled(bool enabled) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'setYtAutoUpdateEnabled',
        {'enabled': enabled},
      );
      return result ?? enabled;
    } on MissingPluginException {
      return enabled;
    }
  }

  @override
  Future<YtRestoreResult> restoreBundledYtEngine() async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
      'restoreBundledYtEngine',
    );
    return YtRestoreResult.fromMap(raw ?? const <String, dynamic>{});
  }

  @override
  Future<void> setQueueAndPlay({
    required List<AudioTrack> tracks,
    required int startIndex,
    bool autoPlay = true,
    int startPositionMs = 0,
  }) async {
    await _methodChannel.invokeMethod<void>('setQueueAndPlay', {
      'tracks': tracks.map((t) => t.toMap()).toList(),
      'startIndex': startIndex,
      'autoPlay': autoPlay,
      'startPositionMs': startPositionMs,
    });
  }

  @override
  Future<void> addToQueue({
    required AudioTrack track,
    int? insertIndex,
  }) async {
    await _methodChannel.invokeMethod<void>('addToQueue', {
      'track': track.toMap(),
      if (insertIndex != null) 'insertIndex': insertIndex,
    });
  }

  @override
  Future<void> moveQueueItem({
    required int fromIndex,
    required int toIndex,
  }) async {
    await _methodChannel.invokeMethod<void>('moveQueueItem', {
      'fromIndex': fromIndex,
      'toIndex': toIndex,
    });
  }

  @override
  Future<void> removeQueueItem({required int index}) async {
    await _methodChannel.invokeMethod<void>('removeQueueItem', {
      'index': index,
    });
  }

  @override
  Future<void> play() => _methodChannel.invokeMethod<void>('play');

  @override
  Future<void> pause() => _methodChannel.invokeMethod<void>('pause');

  @override
  Future<void> seekTo(Duration position) => _methodChannel.invokeMethod<void>(
        'seekTo',
        {'positionMs': position.inMilliseconds},
      );

  @override
  Future<void> skipNext() => _methodChannel.invokeMethod<void>('skipNext');

  @override
  Future<void> skipPrevious() =>
      _methodChannel.invokeMethod<void>('skipPrevious');

  @override
  Future<void> skipToIndex(int index) => _methodChannel.invokeMethod<void>(
        'skipToIndex',
        {'index': index},
      );

  @override
  Future<void> setShuffle(bool enabled) => _methodChannel.invokeMethod<void>(
        'setShuffle',
        {'enabled': enabled},
      );

  @override
  Future<void> setAuraRepeatMode(AuraRepeatMode mode) =>
      _methodChannel.invokeMethod<void>(
        'setRepeatMode',
        {'mode': mode.name},
      );

  @override
  Future<EqualizerState> getEqualizerState() async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getEqualizerState',
      );
      return EqualizerState.fromMap(raw ?? const <String, dynamic>{});
    } on MissingPluginException {
      return const EqualizerState();
    }
  }

  @override
  Future<EqualizerState> updateEqualizerState(EqualizerState state) async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'updateEqualizerState',
        {
          'enabled': state.enabled,
          'presetId': state.presetId,
          'preampDb': state.preampDb,
          'limiterEnabled': state.limiterEnabled,
          'bandGainsDb': state.bandGainsDb,
        },
      );
      return EqualizerState.fromMap(raw ?? const <String, dynamic>{});
    } on MissingPluginException {
      return state;
    }
  }

  @override
  Future<Spatial8dState> getSpatial8dState() async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getSpatial8dState',
      );
      return Spatial8dState.fromMap(raw ?? const <String, dynamic>{});
    } on MissingPluginException {
      return const Spatial8dState();
    }
  }

  @override
  Future<Spatial8dState> updateSpatial8dState(Spatial8dState state) async {
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'updateSpatial8dState',
        {
          'enabled': state.enabled,
          'mode': state.modeWireValue,
          'speedHz': state.speedHz,
          'intensity': state.intensity,
        },
      );
      return Spatial8dState.fromMap(raw ?? const <String, dynamic>{});
    } on MissingPluginException {
      return state;
    }
  }

  @override
  Future<LosslessWebpResult> convertImageToLosslessWebp({
    required String sourcePath,
    required String trackId,
  }) async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
      'convertImageToLosslessWebp',
      {
        'sourcePath': sourcePath,
        'trackId': trackId,
      },
    );
    final map = raw ?? const <String, dynamic>{};
    return LosslessWebpResult(
      webpPath: (map['webpPath'] ?? '').toString(),
      byteSize: (map['byteSize'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      isLossless: map['isLossless'] == true,
    );
  }

  @override
  Future<String> commitCustomArtwork({
    required String pendingPath,
    required String trackId,
  }) async {
    final result = await _methodChannel.invokeMethod<String>(
      'commitCustomArtwork',
      {
        'pendingPath': pendingPath,
        'trackId': trackId,
      },
    );
    return result ?? pendingPath;
  }

  @override
  Future<void> deleteCustomArtworks(String trackId) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'deleteCustomArtworks',
        {'trackId': trackId},
      );
    } on MissingPluginException {
      // Ignorado fuera de Android nativo
    }
  }

  @override
  Future<void> deleteTrackResources({
    required String trackId,
    required String trackUri,
  }) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'deleteTrackResources',
        {
          'trackId': trackId,
          'trackUri': trackUri,
        },
      );
    } on MissingPluginException {
      // Ignorado fuera de Android nativo
    }
  }

  @override
  Future<void> updateMediaItemMetadata(AudioTrack track) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'updateMediaItemMetadata',
        {'track': track.toMap()},
      );
    } on MissingPluginException {
      // Ignorado fuera de Android nativo
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _playbackController.close();
    _importController.close();
    _downloadProgressController.close();
    _ytUpdateProgressController.close();
    _spatial8dController.close();
    _errorController.close();
  }
}
