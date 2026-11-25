// =============================================================================
// library_database.dart — Persistencia local rápida con SQLite (sqflite)
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Guarda únicamente las canciones y playlists locales importadas por la
//   usuaria, permitiendo que Aura Music abra en milisegundos sin volver a leer
//   etiquetas de disco en cada arranque.
// =============================================================================

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/audio_track.dart';

class LibraryDatabase {
  static const _dbName = 'aura_music_library.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, _dbName);
    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tracks (
            id TEXT PRIMARY KEY,
            uri TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            folderName TEXT NOT NULL,
            durationMs INTEGER NOT NULL,
            mimeType TEXT NOT NULL,
            bitrateKbps INTEGER NOT NULL DEFAULT 0,
            sampleRateHz INTEGER NOT NULL DEFAULT 0,
            artworkPath TEXT,
            isFavorite INTEGER NOT NULL DEFAULT 0,
            importedAtMs INTEGER NOT NULL DEFAULT 0,
            lastPlayedAtMs INTEGER NOT NULL DEFAULT 0,
            playCount INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE playlists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            createdAtMs INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE playlist_tracks (
            playlistId TEXT NOT NULL,
            trackId TEXT NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (playlistId, trackId)
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<AudioTrack>> getAllTracks() async {
    final db = await _open();
    final rows = await db.query('tracks', orderBy: 'importedAtMs DESC, title ASC');
    return rows.map(AudioTrack.fromMap).toList();
  }

  Future<void> upsertTracks(List<AudioTrack> tracks) async {
    if (tracks.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final track in tracks) {
      batch.insert(
        'tracks',
        track.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateFavorite(String trackId, bool isFavorite) async {
    final db = await _open();
    await db.update(
      'tracks',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> recordPlayback(String trackId) async {
    final db = await _open();
    await db.rawUpdate(
      'UPDATE tracks SET playCount = playCount + 1, lastPlayedAtMs = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, trackId],
    );
  }

  Future<void> deleteTrack(String trackId) async {
    final db = await _open();
    await db.delete('playlist_tracks', where: 'trackId = ?', whereArgs: [trackId]);
    await db.delete('tracks', where: 'id = ?', whereArgs: [trackId]);
  }

  Future<List<LocalPlaylistRecord>> getPlaylists() async {
    final db = await _open();
    final playlists = await db.query('playlists', orderBy: 'createdAtMs DESC');
    final result = <LocalPlaylistRecord>[];
    for (final pl in playlists) {
      final plId = pl['id'] as String;
      final links = await db.query(
        'playlist_tracks',
        where: 'playlistId = ?',
        whereArgs: [plId],
        orderBy: 'position ASC',
      );
      result.add(
        LocalPlaylistRecord(
          id: plId,
          name: pl['name'] as String,
          createdAtMs: (pl['createdAtMs'] as num).toInt(),
          trackIds: links.map((l) => l['trackId'] as String).toList(),
        ),
      );
    }
    return result;
  }

  Future<LocalPlaylistRecord> createPlaylist(String name) async {
    final db = await _open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'pl_$now';
    await db.insert('playlists', {
      'id': id,
      'name': name.trim(),
      'createdAtMs': now,
    });
    return LocalPlaylistRecord(
      id: id,
      name: name.trim(),
      createdAtMs: now,
      trackIds: const [],
    );
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final db = await _open();
    final countResult = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS nextPos FROM playlist_tracks WHERE playlistId = ?',
      [playlistId],
    );
    final nextPos = (countResult.first['nextPos'] as num?)?.toInt() ?? 0;
    await db.insert(
      'playlist_tracks',
      {
        'playlistId': playlistId,
        'trackId': trackId,
        'position': nextPos,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deletePlaylist(String playlistId) async {
    final db = await _open();
    await db.delete('playlist_tracks', where: 'playlistId = ?', whereArgs: [playlistId]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }
}
