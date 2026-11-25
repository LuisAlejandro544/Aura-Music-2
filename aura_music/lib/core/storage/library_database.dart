// =============================================================================
// library_database.dart — Persistencia local rápida con SQLite (sqflite)
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Guarda únicamente las canciones y playlists locales importadas por la
//   usuaria, permitiendo que Aura Music abra en milisegundos sin volver a leer
//   etiquetas de disco en cada arranque.
// =============================================================================

import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/audio_track.dart';

class LibraryDatabase {
  static const _dbName = 'aura_music_library.db';
  static const _dbVersion = 3;
  static const _feedCacheKey = 'personalized_v1';

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
            originalArtworkPath TEXT,
            hasCustomMetadata INTEGER NOT NULL DEFAULT 0,
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

        await _createExploreTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          final info = await db.rawQuery('PRAGMA table_info(tracks)');
          final cols = info.map((r) => r['name'] as String).toSet();
          if (!cols.contains('originalArtworkPath')) {
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN originalArtworkPath TEXT',
            );
            await db.execute(
              'UPDATE tracks SET originalArtworkPath = artworkPath WHERE originalArtworkPath IS NULL',
            );
          }
          if (!cols.contains('hasCustomMetadata')) {
            await db.execute(
              'ALTER TABLE tracks ADD COLUMN hasCustomMetadata INTEGER NOT NULL DEFAULT 0',
            );
          }
        }
        if (oldVersion < 3) {
          await _createExploreTables(db);
        }
      },
    );
    return _db!;
  }

  Future<void> _createExploreTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS explore_signals (
        videoId TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        webpageUrl TEXT NOT NULL DEFAULT '',
        thumbnailUrl TEXT NOT NULL DEFAULT '',
        durationMs INTEGER NOT NULL DEFAULT 0,
        playCount INTEGER NOT NULL DEFAULT 0,
        completeCount INTEGER NOT NULL DEFAULT 0,
        skipCount INTEGER NOT NULL DEFAULT 0,
        queueCount INTEGER NOT NULL DEFAULT 0,
        downloaded INTEGER NOT NULL DEFAULT 0,
        lastInteractedAtMs INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS track_youtube_seeds (
        trackId TEXT PRIMARY KEY,
        videoId TEXT NOT NULL,
        updatedAtMs INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS explore_feed_cache (
        cacheKey TEXT PRIMARY KEY,
        payloadJson TEXT NOT NULL,
        updatedAtMs INTEGER NOT NULL
      )
    ''');
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

  Future<void> updateTrackMetadata(AudioTrack track) async {
    final db = await _open();
    await db.update(
      'tracks',
      {
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'folderName': track.folderName,
        'artworkPath': track.artworkPath,
        'originalArtworkPath': track.originalArtworkPath,
        'hasCustomMetadata': track.hasCustomMetadata ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [track.id],
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

  Future<List<ExploreSignalRecord>> getExploreSignals({int limit = 120}) async {
    final db = await _open();
    final rows = await db.query(
      'explore_signals',
      orderBy: 'lastInteractedAtMs DESC',
      limit: limit,
    );
    return rows.map(ExploreSignalRecord.fromMap).toList();
  }

  Future<void> recordExploreSignal({
    required String videoId,
    required String title,
    required String artist,
    String webpageUrl = '',
    String thumbnailUrl = '',
    int durationMs = 0,
    bool played = false,
    bool completed = false,
    bool skippedEarly = false,
    bool queued = false,
    bool downloaded = false,
  }) async {
    final cleanId = videoId.trim();
    if (cleanId.isEmpty) return;
    final db = await _open();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.rawInsert(
      '''
      INSERT INTO explore_signals (
        videoId, title, artist, webpageUrl, thumbnailUrl, durationMs,
        playCount, completeCount, skipCount, queueCount, downloaded, lastInteractedAtMs
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(videoId) DO UPDATE SET
        title = CASE WHEN excluded.title != '' THEN excluded.title ELSE explore_signals.title END,
        artist = CASE WHEN excluded.artist != '' THEN excluded.artist ELSE explore_signals.artist END,
        webpageUrl = CASE WHEN excluded.webpageUrl != '' THEN excluded.webpageUrl ELSE explore_signals.webpageUrl END,
        thumbnailUrl = CASE WHEN excluded.thumbnailUrl != '' THEN excluded.thumbnailUrl ELSE explore_signals.thumbnailUrl END,
        durationMs = CASE WHEN excluded.durationMs > 0 THEN excluded.durationMs ELSE explore_signals.durationMs END,
        playCount = explore_signals.playCount + excluded.playCount,
        completeCount = explore_signals.completeCount + excluded.completeCount,
        skipCount = explore_signals.skipCount + excluded.skipCount,
        queueCount = explore_signals.queueCount + excluded.queueCount,
        downloaded = MAX(explore_signals.downloaded, excluded.downloaded),
        lastInteractedAtMs = excluded.lastInteractedAtMs
      ''',
      [
        cleanId,
        title.trim(),
        artist.trim(),
        webpageUrl.trim(),
        thumbnailUrl.trim(),
        durationMs,
        played ? 1 : 0,
        completed ? 1 : 0,
        skippedEarly ? 1 : 0,
        queued ? 1 : 0,
        downloaded ? 1 : 0,
        now,
      ],
    );
  }

  Future<Map<String, String>> getTrackYoutubeSeeds() async {
    final db = await _open();
    final rows = await db.query('track_youtube_seeds');
    return {
      for (final row in rows)
        if ((row['trackId'] ?? '').toString().isNotEmpty &&
            (row['videoId'] ?? '').toString().isNotEmpty)
          row['trackId'].toString(): row['videoId'].toString(),
    };
  }

  Future<void> saveTrackYoutubeSeeds(Map<String, String> seeds) async {
    if (seeds.isEmpty) return;
    final db = await _open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    seeds.forEach((trackId, videoId) {
      if (trackId.trim().isNotEmpty && videoId.trim().isNotEmpty) {
        batch.insert(
          'track_youtube_seeds',
          {
            'trackId': trackId.trim(),
            'videoId': videoId.trim(),
            'updatedAtMs': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    await batch.commit(noResult: true);
  }

  Future<ExplorePersonalizedFeed?> getCachedExploreFeed({
    Duration maxAge = const Duration(hours: 6),
  }) async {
    final db = await _open();
    final rows = await db.query(
      'explore_feed_cache',
      where: 'cacheKey = ?',
      whereArgs: [_feedCacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final updatedAtMs = (row['updatedAtMs'] as num?)?.toInt() ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - updatedAtMs;
    if (ageMs > maxAge.inMilliseconds) return null;

    try {
      final rawJson = (row['payloadJson'] ?? '').toString();
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        final feed = ExplorePersonalizedFeed.fromMap(decoded);
        return feed.isEmpty ? null : feed;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> saveCachedExploreFeed(ExplorePersonalizedFeed feed) async {
    if (feed.isEmpty) return;
    final db = await _open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'explore_feed_cache',
      {
        'cacheKey': _feedCacheKey,
        'payloadJson': jsonEncode(feed.toMap()),
        'updatedAtMs': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearCachedExploreFeed() async {
    final db = await _open();
    await db.delete(
      'explore_feed_cache',
      where: 'cacheKey = ?',
      whereArgs: [_feedCacheKey],
    );
  }
}
