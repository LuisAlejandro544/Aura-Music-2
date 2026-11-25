// =============================================================================
// taste_profiler.dart — Perfilador de gustos musical local (sin servidor)
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Calcula las afinidades de artistas, canciones semilla, duración preferida
//   y exclusiones (pistas ya guardadas o saltadas) usando únicamente datos
//   locales de SQLite (`tracks`, `explore_signals`, `track_youtube_seeds`) y
//   decaimiento temporal exponencial (~21 días de vida media).
//   No envía telemetría ni requiere servidor propio: genera un payload compacto
//   para que `aura_yt_engine.py` consulte Mixes RD de YouTube y reordena las
//   categorías y secciones de Explorar directamente en el dispositivo.
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;
import '../models/audio_track.dart';

class SeedArtistScore {
  const SeedArtistScore({required this.name, required this.score});

  final String name;
  final double score;

  Map<String, dynamic> toMap() => {
        'name': name,
        'score': double.parse(score.toStringAsFixed(3)),
      };
}

class SeedTrackCandidate {
  const SeedTrackCandidate({
    required this.trackId,
    required this.videoId,
    required this.title,
    required this.artist,
    required this.score,
  });

  final String trackId;
  final String videoId;
  final String title;
  final String artist;
  final double score;

  Map<String, dynamic> toMap() => {
        'trackId': trackId,
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'score': double.parse(score.toStringAsFixed(3)),
      };
}

class TasteProfilePayload {
  const TasteProfilePayload({
    required this.seedTracks,
    required this.seedArtists,
    required this.recentQueries,
    required this.excludeVideoIds,
    required this.excludeTitleKeys,
    required this.preferredDurationMs,
    required this.hasSignals,
  });

  final List<SeedTrackCandidate> seedTracks;
  final List<SeedArtistScore> seedArtists;
  final List<String> recentQueries;
  final Set<String> excludeVideoIds;
  final Set<String> excludeTitleKeys;
  final int preferredDurationMs;
  final bool hasSignals;

  String toJsonString() {
    return jsonEncode({
      'seedTracks': seedTracks.map((s) => s.toMap()).toList(growable: false),
      'seedArtists': seedArtists.map((a) => a.toMap()).toList(growable: false),
      'recentQueries': recentQueries,
      'excludeVideoIds': excludeVideoIds.toList(growable: false),
      'preferredDurationMs': preferredDurationMs,
    });
  }
}

class TasteProfiler {
  const TasteProfiler._();

  static const Set<String> _genericArtists = {
    '',
    'artista desconocido',
    'unknown artist',
    'unknown',
    'sin álbum',
    'sin album',
    'música importada',
    'musica importada',
    'descargas aura',
    'explorar aura',
    'various artists',
    'varios artistas',
  };

  static final RegExp _ytIdRegex = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final RegExp _noiseParenRegex = RegExp(
    r'(\(|\[)\s*(official\s*(music\s*)?(video|audio|lyric\s*video|visualizer)|'
    r'video\s*oficial|audio\s*oficial|letra|lyrics?|hd|4k|hq|remastered(\s*\d{4})?|'
    r'en\s*vivo|live)\s*(\)|\])',
    caseSensitive: false,
  );
  static final RegExp _nonWordRegex = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);

  static bool isGenericArtist(String artist) {
    final normalized = artist.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return _genericArtists.contains(normalized) || normalized.startsWith('track ');
  }

  static String normalizeTitle(String title) {
    final withoutNoise = title.replaceAll(_noiseParenRegex, ' ');
    final clean = withoutNoise
        .toLowerCase()
        .replaceAll(_nonWordRegex, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean;
  }

  static String titleArtistKey(String title, String artist) {
    final normTitle = normalizeTitle(title);
    if (normTitle.isEmpty) return '';
    final normArtist = artist.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '$normTitle::$normArtist';
  }

  static String extractYoutubeVideoId(
    AudioTrack track, {
    Map<String, String> cachedSeedVideoIds = const {},
  }) {
    final fromStream = track.streamVideoId;
    if (_ytIdRegex.hasMatch(fromStream)) return fromStream;

    final fromCache = cachedSeedVideoIds[track.id] ?? '';
    if (_ytIdRegex.hasMatch(fromCache)) return fromCache;

    if (track.id.startsWith('yt_')) {
      final raw = track.id.substring(3);
      if (_ytIdRegex.hasMatch(raw)) return raw;
    }

    final parsedUri = Uri.tryParse(track.uri);
    final segments = parsedUri?.pathSegments ?? const <String>[];
    if (segments.isNotEmpty) {
      final last = segments.last;
      final dotIdx = last.lastIndexOf('.');
      final stem = dotIdx > 0 ? last.substring(0, dotIdx) : last;
      if (_ytIdRegex.hasMatch(stem) &&
          (track.album == 'Descargas Aura' ||
              track.uri.contains('yt_downloads') ||
              track.folderName.toLowerCase().contains('aura'))) {
        return stem;
      }
    }

    return '';
  }

  static double _timeDecay(int timestampMs, int nowMs) {
    if (timestampMs <= 0 || nowMs <= timestampMs) {
      return timestampMs <= 0 ? 0.45 : 1.0;
    }
    final ageDays = (nowMs - timestampMs) / 86400000.0;
    return math.exp(-math.ln2 * ageDays / 21.0).clamp(0.08, 1.0);
  }

  static TasteProfilePayload buildProfile({
    required List<AudioTrack> localTracks,
    required List<ExploreSignalRecord> exploreSignals,
    required Map<String, String> cachedSeedVideoIds,
    required List<String> recentQueries,
    int? nowMs,
  }) {
    final currentMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final artistScores = <String, double>{};
    final artistDisplayNames = <String, String>{};
    final seedCandidates = <SeedTrackCandidate>[];
    final excludeVideoIds = <String>{};
    final excludeTitleKeys = <String>{};
    final preferredDurations = <int>[];

    void addArtistScore(String rawArtist, double delta) {
      if (isGenericArtist(rawArtist)) return;
      final key = rawArtist.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      artistDisplayNames.putIfAbsent(key, () => rawArtist.trim());
      artistScores[key] = (artistScores[key] ?? 0.0) + delta;
    }

    // 1. Pistas locales en biblioteca (importadas y descargadas)
    for (final track in localTracks) {
      final activityTs =
          track.lastPlayedAtMs > 0 ? track.lastPlayedAtMs : track.importedAtMs;
      final decay = _timeDecay(activityTs, currentMs);
      final cappedPlays = math.min(track.playCount, 25);
      final score = (1.2 +
              (cappedPlays * 1.4) +
              (track.isFavorite ? 6.0 : 0.0)) *
          decay;

      addArtistScore(track.artist, score);

      if (track.durationMs >= 45000 && track.durationMs <= 900000) {
        preferredDurations.add(track.durationMs);
      }

      final titleKey = titleArtistKey(track.title, track.artist);
      if (titleKey.isNotEmpty) {
        excludeTitleKeys.add(titleKey);
      }

      final vid = extractYoutubeVideoId(
        track,
        cachedSeedVideoIds: cachedSeedVideoIds,
      );
      if (vid.isNotEmpty) {
        excludeVideoIds.add(vid);
      }

      if (track.title.trim().isNotEmpty && !track.isStreamTrack) {
        seedCandidates.add(
          SeedTrackCandidate(
            trackId: track.id,
            videoId: vid,
            title: track.title.trim(),
            artist: isGenericArtist(track.artist) ? '' : track.artist.trim(),
            score: score + (vid.isNotEmpty ? 1.5 : 0.0),
          ),
        );
      }
    }

    // 2. Señales implícitas de Explorar (streamings completos, skips, colas, descargas)
    bool hasPositiveSignal = localTracks.isNotEmpty;
    for (final sig in exploreSignals) {
      final decay = _timeDecay(sig.lastInteractedAtMs, currentMs);
      final raw = (sig.playCount * 0.8) +
          (sig.completeCount * 3.0) +
          (sig.queueCount * 1.5) +
          (sig.downloaded ? 5.0 : 0.0) -
          (sig.skipCount * 1.5);
      final weighted = raw * decay;

      final isRepeatedSkip =
          sig.skipCount >= 2 && sig.completeCount == 0 && !sig.downloaded;
      if (isRepeatedSkip) {
        excludeVideoIds.add(sig.videoId);
        final key = titleArtistKey(sig.title, sig.artist);
        if (key.isNotEmpty) excludeTitleKeys.add(key);
      }

      if (sig.downloaded) {
        excludeVideoIds.add(sig.videoId);
      }

      addArtistScore(sig.artist, weighted);

      if (weighted > 0.25 && sig.title.trim().isNotEmpty && !isRepeatedSkip) {
        hasPositiveSignal = true;
        if (sig.durationMs >= 45000 && sig.durationMs <= 900000) {
          preferredDurations.add(sig.durationMs);
        }
        // Evita duplicar si el mismo videoId ya vino por pista local descargada
        final existingIdx =
            seedCandidates.indexWhere((c) => c.videoId == sig.videoId);
        if (existingIdx >= 0) {
          final prev = seedCandidates[existingIdx];
          seedCandidates[existingIdx] = SeedTrackCandidate(
            trackId: prev.trackId,
            videoId: prev.videoId,
            title: prev.title,
            artist: prev.artist,
            score: prev.score + weighted,
          );
        } else {
          seedCandidates.add(
            SeedTrackCandidate(
              trackId: 'yt_${sig.videoId}',
              videoId: sig.videoId,
              title: sig.title.trim(),
              artist: isGenericArtist(sig.artist) ? '' : sig.artist.trim(),
              score: weighted + 1.0,
            ),
          );
        }
      }
    }

    final cleanQueries = recentQueries
        .map((q) => q.trim())
        .where((q) => q.isNotEmpty && !q.toLowerCase().startsWith('http'))
        .take(5)
        .toList(growable: false);
    if (cleanQueries.isNotEmpty) {
      hasPositiveSignal = true;
    }

    seedCandidates.sort((a, b) => b.score.compareTo(a.score));

    // Diversifica las semillas elegidas para que el top 2 no sea siempre del mismo artista
    final pickedSeeds = <SeedTrackCandidate>[];
    final usedSeedArtists = <String>{};
    for (final cand in seedCandidates) {
      if (pickedSeeds.length >= 4) break;
      final artistKey = cand.artist.toLowerCase();
      if (pickedSeeds.length < 2 &&
          artistKey.isNotEmpty &&
          usedSeedArtists.contains(artistKey)) {
        continue;
      }
      if (artistKey.isNotEmpty) usedSeedArtists.add(artistKey);
      pickedSeeds.add(cand);
    }
    if (pickedSeeds.length < 4) {
      for (final cand in seedCandidates) {
        if (pickedSeeds.length >= 4) break;
        if (!pickedSeeds.any((p) => p.trackId == cand.trackId)) {
          pickedSeeds.add(cand);
        }
      }
    }

    final rankedArtists = artistScores.entries
        .where((e) => e.value > 0.1)
        .map(
          (e) => SeedArtistScore(
            name: artistDisplayNames[e.key] ?? e.key,
            score: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    var preferredDurationMs = 210000;
    if (preferredDurations.isNotEmpty) {
      preferredDurations.sort();
      preferredDurationMs = preferredDurations[preferredDurations.length ~/ 2];
    }

    return TasteProfilePayload(
      seedTracks: pickedSeeds,
      seedArtists: rankedArtists.take(8).toList(growable: false),
      recentQueries: cleanQueries,
      excludeVideoIds: excludeVideoIds,
      excludeTitleKeys: excludeTitleKeys,
      preferredDurationMs: preferredDurationMs,
      hasSignals: hasPositiveSignal,
    );
  }

  /// Reordena las categorías curadas según coincidencia de palabras con artistas,
  /// títulos favoritos y búsquedas recientes (conservando el orden base si empata).
  static List<ExploreCategory> rankCategories(
    List<ExploreCategory> categories,
    TasteProfilePayload profile,
  ) {
    if (!profile.hasSignals) return categories;

    final tasteTokens = <String, double>{};
    void addTokens(String text, double weight) {
      for (final token in normalizeTitle(text).split(' ')) {
        if (token.length >= 3) {
          tasteTokens[token] = (tasteTokens[token] ?? 0.0) + weight;
        }
      }
    }

    for (final artist in profile.seedArtists.take(5)) {
      addTokens(artist.name, math.min(artist.score, 12.0));
    }
    for (final track in profile.seedTracks.take(4)) {
      addTokens(track.title, 2.5);
    }
    for (final q in profile.recentQueries) {
      addTokens(q, 4.0);
    }

    if (tasteTokens.isEmpty) return categories;

    final indexed = categories.asMap().entries.map((entry) {
      final cat = entry.value;
      final haystack =
          normalizeTitle('${cat.title} ${cat.subtitle} ${cat.query}');
      double matchScore = 0.0;
      for (final word in haystack.split(' ')) {
        matchScore += tasteTokens[word] ?? 0.0;
      }
      return (idx: entry.key, cat: cat, score: matchScore);
    }).toList();

    indexed.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      return cmp != 0 ? cmp : a.idx.compareTo(b.idx);
    });

    return indexed.map((e) => e.cat).toList(growable: false);
  }

  /// Filtra pistas ya descargadas/saltadas (incluso en feeds cacheados) y
  /// equilibra artistas para mantener variedad (~70% foco / 30% variedad).
  static ExplorePersonalizedFeed rerankPersonalizedFeed(
    ExplorePersonalizedFeed feed,
    TasteProfilePayload profile,
  ) {
    List<ExploreTrackItem> filterList(
      List<ExploreTrackItem> items, {
      bool diversifyArtists = false,
    }) {
      final primary = <ExploreTrackItem>[];
      final overflow = <ExploreTrackItem>[];
      final artistCounts = <String, int>{};

      for (final item in items) {
        if (profile.excludeVideoIds.contains(item.videoId)) continue;
        final tKey = titleArtistKey(item.title, item.artist);
        if (tKey.isNotEmpty && profile.excludeTitleKeys.contains(tKey)) {
          continue;
        }
        if (!diversifyArtists || isGenericArtist(item.artist)) {
          primary.add(item);
          continue;
        }
        final aKey = item.artist.trim().toLowerCase();
        final seenCount = artistCounts[aKey] ?? 0;
        if (seenCount < 2) {
          artistCounts[aKey] = seenCount + 1;
          primary.add(item);
        } else {
          overflow.add(item);
        }
      }
      return [...primary, ...overflow];
    }

    return feed.copyWith(
      forYou: filterList(feed.forYou, diversifyArtists: true),
      becauseItems: filterList(feed.becauseItems),
      discoveryItems: filterList(feed.discoveryItems, diversifyArtists: true),
    );
  }
}
