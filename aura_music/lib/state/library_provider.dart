// =============================================================================
// library_provider.dart — Estado central de biblioteca importada localmente
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Administra la lista de canciones importadas por el usuario, álbumes,
//   carpetas, playlists locales, favoritos, búsqueda instantánea y progreso de
//   importación SAF. No escanea el teléfono automáticamente en ningún momento.
// =============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/audio/audio_engine_port.dart';
import '../core/models/audio_track.dart';
import '../core/storage/library_database.dart';

enum LibrarySortBy { recent, title, artist, duration }

class LibraryProvider extends ChangeNotifier {
  LibraryProvider({
    required AudioEnginePort engine,
    required LibraryDatabase database,
  })  : _engine = engine,
        _database = database {
    _progressSub = _engine.importProgressEvents.listen((event) {
      _importProcessed = event.processed;
      _importTotal = event.total;
      notifyListeners();
    });
  }

  final AudioEnginePort _engine;
  final LibraryDatabase _database;
  StreamSubscription<({int processed, int total})>? _progressSub;

  List<AudioTrack> _tracks = [];
  List<LocalPlaylistRecord> _playlists = [];
  LibrarySortBy _sortBy = LibrarySortBy.recent;
  bool _isHydrated = false;
  bool _isImporting = false;
  int _importProcessed = 0;
  int _importTotal = 0;
  String? _lastError;

  List<AudioTrack> get tracks => _sortedTracks();
  List<AudioTrack> get favoriteTracks =>
      _tracks.where((t) => t.isFavorite).toList();
  List<AudioTrack> get recentPlayedTracks {
    final played = _tracks.where((t) => t.lastPlayedAtMs > 0).toList()
      ..sort((a, b) => b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs));
    return played.take(8).toList();
  }

  List<AudioTrack> get recentlyImportedTracks {
    final sorted = [..._tracks]
      ..sort((a, b) => b.importedAtMs.compareTo(a.importedAtMs));
    return sorted.take(12).toList();
  }

  LibrarySortBy get sortBy => _sortBy;
  bool get isHydrated => _isHydrated;
  bool get isImporting => _isImporting;
  int get importProcessed => _importProcessed;
  int get importTotal => _importTotal;
  String? get lastError => _lastError;

  List<LocalCollection> get albums {
    final grouped = <String, List<AudioTrack>>{};
    for (final track in _tracks) {
      grouped.putIfAbsent(track.album, () => []).add(track);
    }
    return grouped.entries.map((entry) {
      final first = entry.value.first;
      final art = entry.value
          .map((e) => e.artworkPath)
          .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);
      return LocalCollection(
        id: 'album_${entry.key}',
        title: entry.key,
        subtitle: first.artist,
        type: CollectionType.album,
        tracks: entry.value,
        artworkPath: art,
      );
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  List<LocalCollection> get folders {
    final grouped = <String, List<AudioTrack>>{};
    for (final track in _tracks) {
      grouped.putIfAbsent(track.folderName, () => []).add(track);
    }
    return grouped.entries.map((entry) {
      final art = entry.value
          .map((e) => e.artworkPath)
          .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);
      return LocalCollection(
        id: 'folder_${entry.key}',
        title: entry.key,
        subtitle: 'Carpeta local',
        type: CollectionType.folder,
        tracks: entry.value,
        artworkPath: art,
      );
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  List<LocalCollection> get playlists {
    final byId = {for (final t in _tracks) t.id: t};
    return _playlists.map((pl) {
      final plTracks = pl.trackIds
          .map((id) => byId[id])
          .whereType<AudioTrack>()
          .toList();
      final art = plTracks
          .map((e) => e.artworkPath)
          .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);
      return LocalCollection(
        id: pl.id,
        title: pl.name,
        subtitle: 'Playlist local',
        type: CollectionType.playlist,
        tracks: plTracks,
        artworkPath: art,
      );
    }).toList();
  }

  /// Carga rápida asíncrona tras el primer frame para apertura inmediata.
  Future<void> hydrate() async {
    if (_isHydrated) return;
    try {
      final results = await Future.wait([
        _database.getAllTracks(),
        _database.getPlaylists(),
      ]);
      _tracks = results[0] as List<AudioTrack>;
      _playlists = results[1] as List<LocalPlaylistRecord>;
    } catch (e) {
      _lastError = 'No se pudo cargar la biblioteca local: $e';
    } finally {
      _isHydrated = true;
      notifyListeners();
    }
  }

  void setSortBy(LibrarySortBy sort) {
    if (_sortBy == sort) return;
    _sortBy = sort;
    notifyListeners();
  }

  List<AudioTrack> _sortedTracks() {
    final copy = [..._tracks];
    switch (_sortBy) {
      case LibrarySortBy.recent:
        copy.sort((a, b) => b.importedAtMs.compareTo(a.importedAtMs));
      case LibrarySortBy.title:
        copy.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case LibrarySortBy.artist:
        copy.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case LibrarySortBy.duration:
        copy.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    }
    return copy;
  }

  List<AudioTrack> search(String query, {String filter = 'all'}) {
    final q = query.trim().toLowerCase();
    return _tracks.where((t) {
      final matchesFilter = switch (filter) {
        'lossless' => t.isLossless,
        'favorites' => t.isFavorite,
        _ => true,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q) ||
          t.folderName.toLowerCase().contains(q);
    }).toList();
  }

  Future<int> importFiles() async {
    return _runImport(() => _engine.pickAudioFiles());
  }

  Future<int> importFolder() async {
    return _runImport(() => _engine.pickAudioFolder());
  }

  Future<int> _runImport(Future<List<AudioTrack>> Function() picker) async {
    if (_isImporting) return 0;
    _isImporting = true;
    _importProcessed = 0;
    _importTotal = 0;
    _lastError = null;
    notifyListeners();

    try {
      final imported = await picker();
      if (imported.isEmpty) return 0;

      // Conserva estado de favorito/conteo si la pista ya estaba importada
      final existingById = {for (final t in _tracks) t.id: t};
      final merged = imported.map((t) {
        final prev = existingById[t.id];
        if (prev == null) return t;
        return t.copyWith(
          isFavorite: prev.isFavorite,
          lastPlayedAtMs: prev.lastPlayedAtMs,
          playCount: prev.playCount,
        );
      }).toList();

      await _database.upsertTracks(merged);
      _tracks = await _database.getAllTracks();
      return imported.length;
    } catch (e) {
      _lastError = 'Error al importar música: $e';
      return 0;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(String trackId) async {
    final index = _tracks.indexWhere((t) => t.id == trackId);
    if (index < 0) return;
    final nextFav = !_tracks[index].isFavorite;
    _tracks[index] = _tracks[index].copyWith(isFavorite: nextFav);
    notifyListeners();
    await _database.updateFavorite(trackId, nextFav);
  }

  Future<void> markPlayed(String trackId) async {
    final index = _tracks.indexWhere((t) => t.id == trackId);
    if (index >= 0) {
      final t = _tracks[index];
      _tracks[index] = t.copyWith(
        lastPlayedAtMs: DateTime.now().millisecondsSinceEpoch,
        playCount: t.playCount + 1,
      );
      notifyListeners();
    }
    await _database.recordPlayback(trackId);
  }

  Future<void> removeTrack(String trackId) async {
    _tracks.removeWhere((t) => t.id == trackId);
    notifyListeners();
    await _database.deleteTrack(trackId);
    _playlists = await _database.getPlaylists();
    notifyListeners();
  }

  Future<LocalPlaylistRecord> createPlaylist(String name) async {
    final created = await _database.createPlaylist(name);
    _playlists = [created, ..._playlists];
    notifyListeners();
    return created;
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    await _database.addTrackToPlaylist(playlistId, trackId);
    _playlists = await _database.getPlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((p) => p.id == playlistId);
    notifyListeners();
    await _database.deletePlaylist(playlistId);
  }

  AudioTrack? findById(String id) {
    for (final t in _tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
