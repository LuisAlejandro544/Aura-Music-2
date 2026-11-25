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
            currentIndex: (map['currentIndex'] as num?)?.toInt() ?? 0,
            currentMediaId: map['currentMediaId'] as String?,
            positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
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
  void dispose() {
    _eventSubscription?.cancel();
    _playbackController.close();
    _importController.close();
    _errorController.close();
  }
}
