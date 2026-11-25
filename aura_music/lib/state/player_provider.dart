// =============================================================================
// player_provider.dart — Controlador reactivo de reproducción y cola
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Sincroniza la cola de reproducción, posición actual, Play/Pause, Skip,
//   Shuffle y Repeat con Media3 ExoPlayer (a través de AudioEnginePort),
//   emite señales implícitas locales de streaming (>70% completado, skip <20s)
//   y guarda la última pista/posición para reanudación rápida al abrir Aura Music.
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/audio/audio_engine_port.dart';
import '../core/models/audio_track.dart';
import 'library_provider.dart';

class PlayerProvider extends ChangeNotifier {
  PlayerProvider({
    required AudioEnginePort engine,
    required LibraryProvider library,
  })  : _engine = engine,
        _library = library {
    _playbackSub = _engine.playbackEvents.listen(_onNativePlaybackEvent);
    _spatial8dSub = _engine.spatial8dEvents.listen((event) {
      _spatial8d = event;
      notifyListeners();
    });
    _errorSub = _engine.errorEvents.listen((msg) {
      _errorMessage = msg;
      notifyListeners();
    });
  }

  final AudioEnginePort _engine;
  final LibraryProvider _library;

  StreamSubscription<NativePlaybackEvent>? _playbackSub;
  StreamSubscription<Spatial8dState>? _spatial8dSub;
  StreamSubscription<String>? _errorSub;

  List<AudioTrack> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _shuffleEnabled = false;
  AuraRepeatMode _repeatMode = AuraRepeatMode.off;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;
  bool _isScrubbing = false;
  EqualizerState _equalizer = const EqualizerState();
  int _eqMutationSeq = 0;
  Spatial8dState _spatial8d = const Spatial8dState();
  int _spatial8dMutationSeq = 0;

  AudioTrack? _activeStreamTrack;
  int _activeStreamMaxPosMs = 0;
  int _activeStreamDurationMs = 0;
  bool _recordedStreamCompletion = false;

  void Function(
    AudioTrack track, {
    bool played,
    bool completed,
    bool skippedEarly,
  })? onStreamSignal;

  List<AudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  AudioTrack? get currentTrack {
    if (_queue.isEmpty) return null;
    final live = _queue[_currentIndex.clamp(0, _queue.length - 1)];
    return _library.findById(live.id) ?? live;
  }

  bool get hasActiveTrack => currentTrack != null;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get shuffleEnabled => _shuffleEnabled;
  AuraRepeatMode get repeatMode => _repeatMode;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition;
  Duration get duration =>
      _duration.inMilliseconds > 0 ? _duration : (currentTrack?.duration ?? Duration.zero);
  String? get errorMessage => _errorMessage;
  AudioEngineBackend get activeBackend => _engine.activeBackend;
  EqualizerState get equalizer => _equalizer;
  Spatial8dState get spatial8d => _spatial8d;

  double get progress {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return 0.0;
    return (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  double get bufferedProgress {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return 0.0;
    return (_bufferedPosition.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  /// Inicializa el motor de audio de forma diferida sin bloquear el arranque.
  Future<void> initializeEngineDeferred() async {
    await _engine.initialize();
    _equalizer = await _engine.getEqualizerState();
    _spatial8d = await _engine.getSpatial8dState();
    notifyListeners();
    await _restoreLastSessionIfAvailable();
  }

  Future<void> _restoreLastSessionIfAvailable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastTrackId = prefs.getString('last_track_id');
      final lastPosMs = prefs.getInt('last_pos_ms') ?? 0;
      if (lastTrackId == null || _library.tracks.isEmpty) return;

      final tracks = _library.tracks;
      final idx = tracks.indexWhere((t) => t.id == lastTrackId);
      if (idx < 0) return;

      _queue = tracks;
      _currentIndex = idx;
      _position = Duration(milliseconds: lastPosMs);
      _duration = tracks[idx].duration;
      notifyListeners();

      await _engine.setQueueAndPlay(
        tracks: tracks,
        startIndex: idx,
        autoPlay: false,
        startPositionMs: lastPosMs,
      );
    } catch (_) {
      // Silencioso en caso de primer arranque limpio.
    }
  }

  void _finalizeStreamSession({bool evaluateSkip = true}) {
    final prev = _activeStreamTrack;
    if (prev == null) return;
    if (evaluateSkip &&
        !_recordedStreamCompletion &&
        _activeStreamMaxPosMs > 1000 &&
        _activeStreamMaxPosMs < 20000) {
      onStreamSignal?.call(prev, skippedEarly: true);
    }
    _activeStreamTrack = null;
    _activeStreamMaxPosMs = 0;
    _activeStreamDurationMs = 0;
    _recordedStreamCompletion = false;
  }

  void _beginStreamSession(AudioTrack track) {
    if (!track.isStreamTrack) {
      _activeStreamTrack = null;
      _activeStreamMaxPosMs = 0;
      _activeStreamDurationMs = 0;
      _recordedStreamCompletion = false;
      return;
    }
    _activeStreamTrack = track;
    _activeStreamMaxPosMs = 0;
    _activeStreamDurationMs = track.durationMs;
    _recordedStreamCompletion = false;
    onStreamSignal?.call(track, played: true);
  }

  void _onNativePlaybackEvent(NativePlaybackEvent event) {
    final previousTrackId = currentTrack?.id;
    _isPlaying = event.isPlaying;
    _isBuffering = event.isBuffering;
    _shuffleEnabled = event.shuffleEnabled;
    _repeatMode = event.repeatMode;

    if (_queue.isNotEmpty &&
        event.currentIndex >= 0 &&
        event.currentIndex < _queue.length) {
      _currentIndex = event.currentIndex;
    } else if (event.currentMediaId != null) {
      final found = _queue.indexWhere((t) => t.id == event.currentMediaId);
      if (found >= 0) _currentIndex = found;
    }

    if (!_isScrubbing) {
      _position = Duration(milliseconds: event.positionMs);
    }
    _bufferedPosition = Duration(milliseconds: event.bufferedPositionMs);
    if (event.durationMs > 0) {
      _duration = Duration(milliseconds: event.durationMs);
    }

    final newTrack = currentTrack;
    if (newTrack != null && newTrack.id != previousTrackId) {
      _finalizeStreamSession(evaluateSkip: true);
      if (!newTrack.isStreamTrack) {
        _library.markPlayed(newTrack.id);
        _persistLastSession(newTrack.id, event.positionMs);
      } else {
        _beginStreamSession(newTrack);
      }
    } else if (newTrack != null &&
        _activeStreamTrack != null &&
        _activeStreamTrack!.id == newTrack.id) {
      if (!_isScrubbing && event.positionMs > _activeStreamMaxPosMs) {
        _activeStreamMaxPosMs = event.positionMs;
      }
      if (event.durationMs > 0) {
        _activeStreamDurationMs = event.durationMs;
      }
      final effectiveDur = _activeStreamDurationMs > 0
          ? _activeStreamDurationMs
          : _activeStreamTrack!.durationMs;
      final reachedComplete = effectiveDur > 0
          ? (_activeStreamMaxPosMs >= effectiveDur * 0.70)
          : (_activeStreamMaxPosMs >= 45000);
      if (reachedComplete && !_recordedStreamCompletion) {
        _recordedStreamCompletion = true;
        onStreamSignal?.call(_activeStreamTrack!, completed: true);
      }
    }

    notifyListeners();
  }

  Future<void> playQueue(List<AudioTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final clampedIndex = startIndex.clamp(0, tracks.length - 1);
    final target = tracks[clampedIndex];
    _finalizeStreamSession(evaluateSkip: _activeStreamTrack?.id != target.id);

    _queue = List<AudioTrack>.from(tracks);
    _currentIndex = clampedIndex;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _duration = target.duration;
    _isPlaying = true;
    _isBuffering = target.isStreamTrack;
    _errorMessage = null;
    notifyListeners();

    if (!target.isStreamTrack) {
      _library.markPlayed(target.id);
      _persistLastSession(target.id, 0);
    } else {
      _beginStreamSession(target);
    }

    await _engine.setQueueAndPlay(
      tracks: _queue,
      startIndex: clampedIndex,
      autoPlay: true,
    );
  }

  Future<void> togglePlayPause() async {
    if (!hasActiveTrack) {
      if (_library.tracks.isNotEmpty) {
        await playQueue(_library.tracks, startIndex: 0);
      }
      return;
    }
    if (_isPlaying) {
      _isPlaying = false;
      notifyListeners();
      await _engine.pause();
    } else {
      _isPlaying = true;
      notifyListeners();
      await _engine.play();
    }
  }

  Future<void> skipNext() async {
    if (_queue.isEmpty) return;
    await _engine.skipNext();
  }

  Future<void> skipPrevious() async {
    if (_queue.isEmpty) return;
    await _engine.skipPrevious();
  }

  Future<void> jumpToQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final target = _queue[index];
    _finalizeStreamSession(evaluateSkip: _activeStreamTrack?.id != target.id);
    _currentIndex = index;
    _position = Duration.zero;
    _bufferedPosition = Duration.zero;
    _duration = target.duration;
    _isPlaying = true;
    _isBuffering = target.isStreamTrack;
    notifyListeners();
    if (!target.isStreamTrack) {
      _library.markPlayed(target.id);
      _persistLastSession(target.id, 0);
    } else {
      _beginStreamSession(target);
    }
    await _engine.skipToIndex(index);
  }

  Future<void> addToQueueEnd(AudioTrack track) async {
    if (_queue.isEmpty) {
      await playQueue([track]);
      return;
    }
    final entry = track.copyWith();
    _queue = [..._queue, entry];
    notifyListeners();
    await _engine.addToQueue(track: entry);
  }

  Future<void> playNextInQueue(AudioTrack track) async {
    if (_queue.isEmpty) {
      await playQueue([track]);
      return;
    }
    final entry = track.copyWith();
    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    final updated = [..._queue]..insert(insertIndex, entry);
    _queue = updated;
    notifyListeners();
    await _engine.addToQueue(track: entry, insertIndex: insertIndex);
  }

  Future<void> reorderQueueItem(int oldIndex, int targetIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        targetIndex < 0 ||
        targetIndex >= _queue.length ||
        oldIndex == targetIndex) {
      return;
    }
    final updated = [..._queue];
    final moved = updated.removeAt(oldIndex);
    updated.insert(targetIndex, moved);
    _queue = updated;

    if (oldIndex == _currentIndex) {
      _currentIndex = targetIndex;
    } else if (oldIndex < _currentIndex && targetIndex >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && targetIndex <= _currentIndex) {
      _currentIndex += 1;
    }

    notifyListeners();
    await _engine.moveQueueItem(fromIndex: oldIndex, toIndex: targetIndex);
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final updated = [..._queue]..removeAt(index);
    _queue = updated;

    if (_queue.isEmpty) {
      _currentIndex = 0;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    } else if (index < _currentIndex) {
      _currentIndex -= 1;
    } else if (index == _currentIndex) {
      _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
      _position = Duration.zero;
      _duration = _queue[_currentIndex].duration;
    }

    notifyListeners();
    await _engine.removeQueueItem(index: index);
  }

  void beginScrub() {
    _isScrubbing = true;
  }

  void updateScrub(Duration target) {
    _position = target;
    notifyListeners();
  }

  Future<void> endScrub(Duration target) async {
    _position = target;
    _isScrubbing = false;
    notifyListeners();
    await _engine.seekTo(target);
    final current = currentTrack;
    if (current != null && !current.isStreamTrack) {
      _persistLastSession(current.id, target.inMilliseconds);
    }
  }

  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    notifyListeners();
    await _engine.setShuffle(_shuffleEnabled);
  }

  Future<void> cycleAuraRepeatMode() async {
    _repeatMode = switch (_repeatMode) {
      AuraRepeatMode.off => AuraRepeatMode.all,
      AuraRepeatMode.all => AuraRepeatMode.one,
      AuraRepeatMode.one => AuraRepeatMode.off,
    };
    notifyListeners();
    await _engine.setAuraRepeatMode(_repeatMode);
  }

  Future<void> syncUpdatedTrack(AudioTrack updated) async {
    bool touched = false;
    _queue = _queue.map((item) {
      if (item.id == updated.id) {
        touched = true;
        return updated;
      }
      return item;
    }).toList();
    if (touched) {
      notifyListeners();
      await _engine.updateMediaItemMetadata(updated);
    }
  }

  Future<void> refreshEqualizerState() async {
    _equalizer = await _engine.getEqualizerState();
    notifyListeners();
  }

  Future<void> _pushEqualizerState(EqualizerState next) async {
    final seq = ++_eqMutationSeq;
    _equalizer = next;
    notifyListeners();
    final synced = await _engine.updateEqualizerState(next);
    if (seq == _eqMutationSeq) {
      _equalizer = synced;
      notifyListeners();
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) {
    return _pushEqualizerState(_equalizer.copyWith(enabled: enabled));
  }

  Future<void> applyEqualizerPreset(EqualizerPreset preset) {
    return _pushEqualizerState(
      _equalizer.copyWith(
        enabled: true,
        presetId: preset.id,
        preampDb: preset.preampDb,
        bandGainsDb: List<double>.from(preset.bandGainsDb),
      ),
    );
  }

  Future<void> setBandGain(int bandIndex, double gainDb) {
    if (bandIndex < 0 || bandIndex >= 5) return Future.value();
    final updatedBands = List<double>.from(_equalizer.bandGainsDb);
    updatedBands[bandIndex] = gainDb.clamp(-12.0, 12.0);
    return _pushEqualizerState(
      _equalizer.copyWith(
        enabled: true,
        presetId: 'custom',
        bandGainsDb: updatedBands,
      ),
    );
  }

  Future<void> setPreampDb(double preampDb) {
    return _pushEqualizerState(
      _equalizer.copyWith(
        enabled: true,
        preampDb: preampDb.clamp(-6.0, 6.0),
      ),
    );
  }

  Future<void> setLimiterEnabled(bool limiterEnabled) {
    return _pushEqualizerState(
      _equalizer.copyWith(limiterEnabled: limiterEnabled),
    );
  }

  Future<void> resetEqualizer() {
    return _pushEqualizerState(
      _equalizer.copyWith(
        presetId: 'flat',
        preampDb: 0.0,
        limiterEnabled: true,
        bandGainsDb: const [0.0, 0.0, 0.0, 0.0, 0.0],
      ),
    );
  }

  Future<void> refreshSpatial8dState() async {
    _spatial8d = await _engine.getSpatial8dState();
    notifyListeners();
  }

  Future<void> _pushSpatial8dState(Spatial8dState next) async {
    final seq = ++_spatial8dMutationSeq;
    _spatial8d = next;
    notifyListeners();
    final synced = await _engine.updateSpatial8dState(next);
    if (seq == _spatial8dMutationSeq) {
      _spatial8d = synced;
      notifyListeners();
    }
  }

  Future<void> setSpatial8dEnabled(bool enabled) {
    return _pushSpatial8dState(_spatial8d.copyWith(enabled: enabled));
  }

  Future<void> setSpatial8dMode(Spatial8dOutputMode mode) {
    final optimisticResolved = switch (mode) {
      Spatial8dOutputMode.headphones => 'headphones',
      Spatial8dOutputMode.speaker => 'speaker',
      Spatial8dOutputMode.auto => _spatial8d.resolvedOutput,
    };
    return _pushSpatial8dState(
      _spatial8d.copyWith(
        mode: mode,
        resolvedOutput: optimisticResolved,
      ),
    );
  }

  Future<void> setSpatial8dSpeedHz(double speedHz) {
    return _pushSpatial8dState(
      _spatial8d.copyWith(speedHz: speedHz.clamp(0.05, 0.50)),
    );
  }

  Future<void> setSpatial8dIntensity(double intensity) {
    return _pushSpatial8dState(
      _spatial8d.copyWith(intensity: intensity.clamp(0.0, 1.0)),
    );
  }

  Future<void> resetSpatial8d() {
    return _pushSpatial8dState(
      _spatial8d.copyWith(
        mode: Spatial8dOutputMode.auto,
        speedHz: 0.16,
        intensity: 0.75,
      ),
    );
  }

  Future<void> _persistLastSession(String trackId, int posMs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_track_id', trackId);
      await prefs.setInt('last_pos_ms', posMs);
    } catch (_) {}
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _spatial8dSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
