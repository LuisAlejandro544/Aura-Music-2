// =============================================================================
// player_provider.dart — Controlador reactivo de reproducción y cola
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Sincroniza la cola de reproducción, posición actual, Play/Pause, Skip,
//   Shuffle y Repeat con Media3 ExoPlayer (a través de AudioEnginePort) y
//   guarda la última pista/posición para reanudación rápida al abrir Aura Music.
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
    _errorSub = _engine.errorEvents.listen((msg) {
      _errorMessage = msg;
      notifyListeners();
    });
  }

  final AudioEnginePort _engine;
  final LibraryProvider _library;

  StreamSubscription<NativePlaybackEvent>? _playbackSub;
  StreamSubscription<String>? _errorSub;

  List<AudioTrack> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  AuraRepeatMode _repeatMode = AuraRepeatMode.off;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;
  bool _isScrubbing = false;

  List<AudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  AudioTrack? get currentTrack {
    if (_queue.isEmpty) return null;
    final live = _queue[_currentIndex.clamp(0, _queue.length - 1)];
    return _library.findById(live.id) ?? live;
  }

  bool get hasActiveTrack => currentTrack != null;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _shuffleEnabled;
  AuraRepeatMode get repeatMode => _repeatMode;
  Duration get position => _position;
  Duration get duration =>
      _duration.inMilliseconds > 0 ? _duration : (currentTrack?.duration ?? Duration.zero);
  String? get errorMessage => _errorMessage;
  AudioEngineBackend get activeBackend => _engine.activeBackend;

  double get progress {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return 0.0;
    return (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  /// Inicializa el motor de audio de forma diferida sin bloquear el arranque.
  Future<void> initializeEngineDeferred() async {
    await _engine.initialize();
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

  void _onNativePlaybackEvent(NativePlaybackEvent event) {
    final previousTrackId = currentTrack?.id;
    _isPlaying = event.isPlaying;
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
    if (event.durationMs > 0) {
      _duration = Duration(milliseconds: event.durationMs);
    }

    final newTrack = currentTrack;
    if (newTrack != null && newTrack.id != previousTrackId) {
      _library.markPlayed(newTrack.id);
      _persistLastSession(newTrack.id, event.positionMs);
    }

    notifyListeners();
  }

  Future<void> playQueue(List<AudioTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final clampedIndex = startIndex.clamp(0, tracks.length - 1);
    _queue = List<AudioTrack>.from(tracks);
    _currentIndex = clampedIndex;
    _position = Duration.zero;
    _duration = _queue[clampedIndex].duration;
    _isPlaying = true;
    _errorMessage = null;
    notifyListeners();

    final target = _queue[clampedIndex];
    _library.markPlayed(target.id);
    _persistLastSession(target.id, 0);

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
    _currentIndex = index;
    _position = Duration.zero;
    _duration = _queue[index].duration;
    _isPlaying = true;
    notifyListeners();
    await _engine.skipToIndex(index);
  }

  void addToQueueEnd(AudioTrack track) {
    if (_queue.isEmpty) {
      playQueue([track]);
      return;
    }
    _queue = [..._queue, track];
    notifyListeners();
    _engine.setQueueAndPlay(
      tracks: _queue,
      startIndex: _currentIndex,
      autoPlay: _isPlaying,
      startPositionMs: _position.inMilliseconds,
    );
  }

  void playNextInQueue(AudioTrack track) {
    if (_queue.isEmpty) {
      playQueue([track]);
      return;
    }
    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    final updated = [..._queue]..insert(insertIndex, track);
    _queue = updated;
    notifyListeners();
    _engine.setQueueAndPlay(
      tracks: _queue,
      startIndex: _currentIndex,
      autoPlay: _isPlaying,
      startPositionMs: _position.inMilliseconds,
    );
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
    if (current != null) {
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
    _errorSub?.cancel();
    super.dispose();
  }
}
