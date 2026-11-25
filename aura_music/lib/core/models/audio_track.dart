// =============================================================================
// audio_track.dart — Modelos de dominio para pistas, colecciones y estado
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Define las estructuras inmutables que representan una canción importada
//   localmente (AudioTrack), colecciones agrupadas (LocalCollection: álbumes,
//   carpetas o playlists locales), modos de repetición y el estado del motor.
// =============================================================================

import 'package:flutter/foundation.dart';

enum AuraRepeatMode { off, all, one }

enum CollectionType { album, folder, playlist }

enum AudioEngineBackend {
  exoPlayer,
  // Reservado para la versión final cuando se integre procesamiento Rust:
  rustDspFuture,
}

@immutable
class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    required this.folderName,
    required this.durationMs,
    required this.mimeType,
    this.bitrateKbps = 0,
    this.sampleRateHz = 0,
    this.artworkPath,
    this.originalArtworkPath,
    this.hasCustomMetadata = false,
    this.isFavorite = false,
    this.importedAtMs = 0,
    this.lastPlayedAtMs = 0,
    this.playCount = 0,
  });

  final String id;
  final String uri;
  final String title;
  final String artist;
  final String album;
  final String folderName;
  final int durationMs;
  final String mimeType;
  final int bitrateKbps;
  final int sampleRateHz;
  final String? artworkPath;
  final String? originalArtworkPath;
  final bool hasCustomMetadata;
  final bool isFavorite;
  final int importedAtMs;
  final int lastPlayedAtMs;
  final int playCount;

  Duration get duration => Duration(milliseconds: durationMs);
  bool get hasCustomWebpArtwork =>
      (artworkPath ?? '').toLowerCase().endsWith('.webp');

  String get formatBadge {
    final lower = mimeType.toLowerCase();
    if (lower.contains('flac')) return 'FLAC';
    if (lower.contains('wav')) return 'WAV';
    if (lower.contains('ogg') || lower.contains('opus')) return 'OGG';
    if (lower.contains('mp4') || lower.contains('aac') || lower.contains('m4a')) {
      return 'AAC';
    }
    return 'MP3';
  }

  bool get isLossless {
    final badge = formatBadge;
    return badge == 'FLAC' || badge == 'WAV';
  }

  String get technicalSummary {
    final parts = <String>[formatBadge];
    if (bitrateKbps > 0) parts.add('$bitrateKbps kbps');
    if (sampleRateHz > 0) {
      final khz = (sampleRateHz / 1000).toStringAsFixed(1);
      parts.add('$khz kHz');
    }
    return parts.join(' · ');
  }

  AudioTrack copyWith({
    String? title,
    String? artist,
    String? album,
    String? folderName,
    bool? isFavorite,
    int? lastPlayedAtMs,
    int? playCount,
    String? artworkPath,
    bool clearArtworkPath = false,
    String? originalArtworkPath,
    bool clearOriginalArtworkPath = false,
    bool? hasCustomMetadata,
  }) {
    return AudioTrack(
      id: id,
      uri: uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      folderName: folderName ?? this.folderName,
      durationMs: durationMs,
      mimeType: mimeType,
      bitrateKbps: bitrateKbps,
      sampleRateHz: sampleRateHz,
      artworkPath: clearArtworkPath ? null : (artworkPath ?? this.artworkPath),
      originalArtworkPath: clearOriginalArtworkPath
          ? null
          : (originalArtworkPath ?? this.originalArtworkPath),
      hasCustomMetadata: hasCustomMetadata ?? this.hasCustomMetadata,
      isFavorite: isFavorite ?? this.isFavorite,
      importedAtMs: importedAtMs,
      lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
      playCount: playCount ?? this.playCount,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uri': uri,
        'title': title,
        'artist': artist,
        'album': album,
        'folderName': folderName,
        'durationMs': durationMs,
        'mimeType': mimeType,
        'bitrateKbps': bitrateKbps,
        'sampleRateHz': sampleRateHz,
        'artworkPath': artworkPath,
        'originalArtworkPath': originalArtworkPath,
        'hasCustomMetadata': hasCustomMetadata ? 1 : 0,
        'isFavorite': isFavorite ? 1 : 0,
        'importedAtMs': importedAtMs,
        'lastPlayedAtMs': lastPlayedAtMs,
        'playCount': playCount,
      };

  factory AudioTrack.fromMap(Map<String, dynamic> map) {
    final art = map['artworkPath'] as String?;
    final origArt = map['originalArtworkPath'] as String?;
    return AudioTrack(
      id: (map['id'] ?? '').toString(),
      uri: (map['uri'] ?? '').toString(),
      title: (map['title'] ?? 'Pista local').toString(),
      artist: (map['artist'] ?? 'Artista desconocido').toString(),
      album: (map['album'] ?? 'Sin álbum').toString(),
      folderName: (map['folderName'] ?? 'Música Importada').toString(),
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      mimeType: (map['mimeType'] ?? 'audio/mpeg').toString(),
      bitrateKbps: (map['bitrateKbps'] as num?)?.toInt() ?? 0,
      sampleRateHz: (map['sampleRateHz'] as num?)?.toInt() ?? 0,
      artworkPath: art,
      originalArtworkPath: origArt ?? art,
      hasCustomMetadata:
          (map['hasCustomMetadata'] == true) || (map['hasCustomMetadata'] == 1),
      isFavorite: (map['isFavorite'] == true) || (map['isFavorite'] == 1),
      importedAtMs: (map['importedAtMs'] as num?)?.toInt() ?? 0,
      lastPlayedAtMs: (map['lastPlayedAtMs'] as num?)?.toInt() ?? 0,
      playCount: (map['playCount'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class LocalCollection {
  const LocalCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.tracks,
    this.artworkPath,
  });

  final String id;
  final String title;
  final String subtitle;
  final CollectionType type;
  final List<AudioTrack> tracks;
  final String? artworkPath;

  Duration get totalDuration => Duration(
        milliseconds: tracks.fold<int>(0, (sum, t) => sum + t.durationMs),
      );
}

@immutable
class LocalPlaylistRecord {
  const LocalPlaylistRecord({
    required this.id,
    required this.name,
    required this.createdAtMs,
    required this.trackIds,
  });

  final String id;
  final String name;
  final int createdAtMs;
  final List<String> trackIds;
}

@immutable
class NativePlaybackEvent {
  const NativePlaybackEvent({
    required this.isPlaying,
    required this.currentIndex,
    required this.positionMs,
    required this.durationMs,
    required this.shuffleEnabled,
    required this.repeatMode,
    this.currentMediaId,
  });

  final bool isPlaying;
  final int currentIndex;
  final String? currentMediaId;
  final int positionMs;
  final int durationMs;
  final bool shuffleEnabled;
  final AuraRepeatMode repeatMode;
}

@immutable
class LosslessWebpResult {
  const LosslessWebpResult({
    required this.webpPath,
    required this.byteSize,
    required this.width,
    required this.height,
    required this.isLossless,
  });

  final String webpPath;
  final int byteSize;
  final int width;
  final int height;
  final bool isLossless;

  String get formattedSize {
    if (byteSize < 1024) return '$byteSize B';
    if (byteSize < 1024 * 1024) {
      return '${(byteSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(byteSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

enum YtDownloadFormat { best, m4a, opus }

@immutable
class DownloadProgressEvent {
  const DownloadProgressEvent({
    required this.stage,
    required this.percent,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.message,
  });

  final String stage;
  final double percent;
  final int downloadedBytes;
  final int totalBytes;
  final String message;
}

@immutable
class YtEngineStatus {
  const YtEngineStatus({
    required this.pythonVersion,
    required this.ytDlpVersion,
    required this.ejsVersion,
    required this.quickjsReady,
    required this.rustCrate,
    required this.audioProcessor,
    required this.arch,
  });

  final String pythonVersion;
  final String ytDlpVersion;
  final String ejsVersion;
  final bool quickjsReady;
  final String rustCrate;
  final String audioProcessor;
  final String arch;

  factory YtEngineStatus.fromMap(Map<String, dynamic> map) {
    return YtEngineStatus(
      pythonVersion: (map['pythonVersion'] ?? '').toString(),
      ytDlpVersion: (map['ytDlpVersion'] ?? '').toString(),
      ejsVersion: (map['ejsVersion'] ?? '').toString(),
      quickjsReady: map['quickjsReady'] == true,
      rustCrate: (map['rustCrate'] ?? '').toString(),
      audioProcessor: (map['audioProcessor'] ?? '').toString(),
      arch: (map['arch'] ?? '').toString(),
    );
  }
}

@immutable
class YtDownloadFailure implements Exception {
  const YtDownloadFailure({
    required this.summary,
    required this.rawLog,
  });

  final String summary;
  final String rawLog;

  @override
  String toString() => summary;
}
