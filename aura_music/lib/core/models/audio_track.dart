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
    this.sourceUrl = '',
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
  final String sourceUrl;

  Duration get duration => Duration(milliseconds: durationMs);
  bool get hasCustomWebpArtwork =>
      (artworkPath ?? '').toLowerCase().endsWith('.webp');

  bool get isStreamTrack =>
      uri.startsWith('aura-stream://') ||
      uri.startsWith('http://') ||
      uri.startsWith('https://');

  String get streamVideoId {
    if (!uri.startsWith('aura-stream://')) return '';
    return Uri.tryParse(uri)?.queryParameters['id'] ?? '';
  }

  String get effectiveSourceUrl {
    if (sourceUrl.isNotEmpty) return sourceUrl;
    if (uri.startsWith('aura-stream://')) {
      return Uri.tryParse(uri)?.queryParameters['u'] ?? '';
    }
    return '';
  }

  String get formatBadge {
    final lower = mimeType.toLowerCase();
    if (lower.contains('stream')) return 'STREAM';
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
    String? mimeType,
    int? bitrateKbps,
    int? sampleRateHz,
    int? durationMs,
    bool? isFavorite,
    int? lastPlayedAtMs,
    int? playCount,
    String? artworkPath,
    bool clearArtworkPath = false,
    String? originalArtworkPath,
    bool clearOriginalArtworkPath = false,
    bool? hasCustomMetadata,
    String? sourceUrl,
  }) {
    return AudioTrack(
      id: id,
      uri: uri,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      folderName: folderName ?? this.folderName,
      durationMs: durationMs ?? this.durationMs,
      mimeType: mimeType ?? this.mimeType,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      artworkPath: clearArtworkPath ? null : (artworkPath ?? this.artworkPath),
      originalArtworkPath: clearOriginalArtworkPath
          ? null
          : (originalArtworkPath ?? this.originalArtworkPath),
      hasCustomMetadata: hasCustomMetadata ?? this.hasCustomMetadata,
      isFavorite: isFavorite ?? this.isFavorite,
      importedAtMs: importedAtMs,
      lastPlayedAtMs: lastPlayedAtMs ?? this.lastPlayedAtMs,
      playCount: playCount ?? this.playCount,
      sourceUrl: sourceUrl ?? this.sourceUrl,
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
    this.bufferedPositionMs = 0,
    this.isBuffering = false,
    this.currentMediaId,
  });

  final bool isPlaying;
  final bool isBuffering;
  final int currentIndex;
  final String? currentMediaId;
  final int positionMs;
  final int bufferedPositionMs;
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
    required this.pythonStarted,
    required this.pythonVersion,
    required this.ytDlpVersion,
    required this.ejsVersion,
    required this.quickjsReady,
    required this.rustCrate,
    required this.audioProcessor,
    required this.arch,
    this.usingUpdatedYtDlp = false,
    this.usingUpdatedEjs = false,
    this.autoUpdateEnabled = true,
    this.lastUpdateCheckMs = 0,
  });

  final bool pythonStarted;
  final String pythonVersion;
  final String ytDlpVersion;
  final String ejsVersion;
  final bool quickjsReady;
  final String rustCrate;
  final String audioProcessor;
  final String arch;
  final bool usingUpdatedYtDlp;
  final bool usingUpdatedEjs;
  final bool autoUpdateEnabled;
  final int lastUpdateCheckMs;

  bool get hasAnyPyPiOverride => usingUpdatedYtDlp || usingUpdatedEjs;

  factory YtEngineStatus.fromMap(Map<String, dynamic> map) {
    final pyVer = (map['pythonVersion'] ?? '').toString();
    return YtEngineStatus(
      pythonStarted: map['pythonStarted'] == true || pyVer.isNotEmpty,
      pythonVersion: pyVer,
      ytDlpVersion: (map['ytDlpVersion'] ?? '').toString(),
      ejsVersion: (map['ejsVersion'] ?? '').toString(),
      quickjsReady: map['quickjsReady'] == true,
      rustCrate: (map['rustCrate'] ?? '').toString(),
      audioProcessor: (map['audioProcessor'] ?? '').toString(),
      arch: (map['arch'] ?? '').toString(),
      usingUpdatedYtDlp: map['usingUpdatedYtDlp'] == true,
      usingUpdatedEjs: map['usingUpdatedEjs'] == true,
      autoUpdateEnabled: map['autoUpdateEnabled'] != false,
      lastUpdateCheckMs: (map['lastUpdateCheckMs'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class YtPackageUpdateStatus {
  const YtPackageUpdateStatus({
    required this.installed,
    this.previous = '',
    this.latest = '',
    this.updated = false,
    this.updateAvailable = false,
  });

  final String installed;
  final String previous;
  final String latest;
  final bool updated;
  final bool updateAvailable;

  factory YtPackageUpdateStatus.fromMap(Map<String, dynamic>? map) {
    final safe = map ?? const <String, dynamic>{};
    return YtPackageUpdateStatus(
      installed: (safe['installed'] ?? 'unknown').toString(),
      previous: (safe['previous'] ?? '').toString(),
      latest: (safe['latest'] ?? '').toString(),
      updated: safe['updated'] == true,
      updateAvailable: safe['updateAvailable'] == true,
    );
  }
}

@immutable
class YtUpdateCheckResult {
  const YtUpdateCheckResult({
    required this.ok,
    required this.checkedAtMs,
    required this.hasUpdates,
    required this.error,
    required this.ytDlp,
    required this.ytDlpEjs,
  });

  final bool ok;
  final int checkedAtMs;
  final bool hasUpdates;
  final String error;
  final YtPackageUpdateStatus ytDlp;
  final YtPackageUpdateStatus ytDlpEjs;

  factory YtUpdateCheckResult.fromMap(Map<String, dynamic> map) {
    final ytRaw = map['ytDlp'];
    final ejsRaw = map['ytDlpEjs'];
    return YtUpdateCheckResult(
      ok: map['ok'] == true,
      checkedAtMs: (map['checkedAtMs'] as num?)?.toInt() ?? 0,
      hasUpdates: map['hasUpdates'] == true,
      error: (map['error'] ?? '').toString(),
      ytDlp: YtPackageUpdateStatus.fromMap(
        ytRaw is Map ? Map<String, dynamic>.from(ytRaw) : null,
      ),
      ytDlpEjs: YtPackageUpdateStatus.fromMap(
        ejsRaw is Map ? Map<String, dynamic>.from(ejsRaw) : null,
      ),
    );
  }
}

@immutable
class YtUpdateProgressEvent {
  const YtUpdateProgressEvent({
    required this.stage,
    required this.packageName,
    required this.percent,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.message,
  });

  final String stage;
  final String packageName;
  final double percent;
  final int downloadedBytes;
  final int totalBytes;
  final String message;
}

@immutable
class YtUpdateResult {
  const YtUpdateResult({
    required this.ok,
    required this.updatedAny,
    required this.checkedAtMs,
    required this.message,
    required this.error,
    required this.ytDlp,
    required this.ytDlpEjs,
  });

  final bool ok;
  final bool updatedAny;
  final int checkedAtMs;
  final String message;
  final String error;
  final YtPackageUpdateStatus ytDlp;
  final YtPackageUpdateStatus ytDlpEjs;

  factory YtUpdateResult.fromMap(Map<String, dynamic> map) {
    final ytRaw = map['ytDlp'];
    final ejsRaw = map['ytDlpEjs'];
    return YtUpdateResult(
      ok: map['ok'] == true,
      updatedAny: map['updatedAny'] == true,
      checkedAtMs: (map['checkedAtMs'] as num?)?.toInt() ?? 0,
      message: (map['message'] ?? '').toString(),
      error: (map['error'] ?? '').toString(),
      ytDlp: YtPackageUpdateStatus.fromMap(
        ytRaw is Map ? Map<String, dynamic>.from(ytRaw) : null,
      ),
      ytDlpEjs: YtPackageUpdateStatus.fromMap(
        ejsRaw is Map ? Map<String, dynamic>.from(ejsRaw) : null,
      ),
    );
  }
}

@immutable
class YtRestoreResult {
  const YtRestoreResult({
    required this.ok,
    required this.removed,
    required this.ytDlpVersion,
    required this.ejsVersion,
  });

  final bool ok;
  final bool removed;
  final String ytDlpVersion;
  final String ejsVersion;

  factory YtRestoreResult.fromMap(Map<String, dynamic> map) {
    return YtRestoreResult(
      ok: map['ok'] == true,
      removed: map['removed'] == true,
      ytDlpVersion: (map['ytDlpVersion'] ?? '').toString(),
      ejsVersion: (map['ejsVersion'] ?? '').toString(),
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

@immutable
class EqualizerBandInfo {
  const EqualizerBandInfo({
    required this.index,
    required this.freqLabel,
    required this.humanName,
    required this.effectHint,
  });

  final int index;
  final String freqLabel;
  final String humanName;
  final String effectHint;
}

@immutable
class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.preampDb,
    required this.bandGainsDb,
  });

  final String id;
  final String name;
  final String description;
  final double preampDb;
  final List<double> bandGainsDb;
}

@immutable
class EqualizerState {
  const EqualizerState({
    this.enabled = false,
    this.presetId = 'flat',
    this.preampDb = 0.0,
    this.limiterEnabled = true,
    this.bandGainsDb = const [0.0, 0.0, 0.0, 0.0, 0.0],
    this.rustCrate = 'aura_dsp',
    this.engine = 'Biquad IIR 5-band + Soft Limiter',
    this.arch = '',
  });

  final bool enabled;
  final String presetId;
  final double preampDb;
  final bool limiterEnabled;
  final List<double> bandGainsDb;
  final String rustCrate;
  final String engine;
  final String arch;

  static const List<EqualizerBandInfo> bands = [
    EqualizerBandInfo(
      index: 0,
      freqLabel: '60 Hz',
      humanName: 'Subgraves',
      effectHint: 'Vibración y cuerpo profundo',
    ),
    EqualizerBandInfo(
      index: 1,
      freqLabel: '230 Hz',
      humanName: 'Graves',
      effectHint: 'Calidez, bajo y golpe',
    ),
    EqualizerBandInfo(
      index: 2,
      freqLabel: '910 Hz',
      humanName: 'Voces',
      effectHint: 'Claridad de voz e instrumentos',
    ),
    EqualizerBandInfo(
      index: 3,
      freqLabel: '3.6 kHz',
      humanName: 'Presencia',
      effectHint: 'Definición, guitarras y ataque',
    ),
    EqualizerBandInfo(
      index: 4,
      freqLabel: '12 kHz',
      humanName: 'Brillo',
      effectHint: 'Aire, platillos y detalle fino',
    ),
  ];

  static const List<EqualizerPreset> presets = [
    EqualizerPreset(
      id: 'flat',
      name: 'Natural',
      description: 'Sonido original equilibrado sin alteraciones',
      preampDb: 0.0,
      bandGainsDb: [0.0, 0.0, 0.0, 0.0, 0.0],
    ),
    EqualizerPreset(
      id: 'bass_boost',
      name: 'Más Graves',
      description: 'Refuerza bombos, bajos y pegada cálida',
      preampDb: -1.5,
      bandGainsDb: [5.5, 3.5, 0.0, 0.5, 1.0],
    ),
    EqualizerPreset(
      id: 'vocal_clarity',
      name: 'Voces Claras',
      description: 'Resalta voces y letras sobre el fondo musical',
      preampDb: -0.5,
      bandGainsDb: [-1.5, 0.0, 3.5, 3.0, 1.5],
    ),
    EqualizerPreset(
      id: 'acoustic_warmth',
      name: 'Acústico Cálido',
      description: 'Ideal para guitarras, pianos y lo-fi suave',
      preampDb: -0.5,
      bandGainsDb: [2.0, 2.5, 1.5, 2.0, 2.5],
    ),
    EqualizerPreset(
      id: 'treble_sparkle',
      name: 'Más Brillo',
      description: 'Aporta aire, platillos y sensación abierta',
      preampDb: -1.0,
      bandGainsDb: [0.5, 0.0, 1.0, 3.5, 5.0],
    ),
    EqualizerPreset(
      id: 'night_mode',
      name: 'Noche',
      description: 'Suaviza graves intensos para escuchar bajo',
      preampDb: 0.0,
      bandGainsDb: [-4.0, -2.0, 2.5, 1.5, -1.5],
    ),
  ];

  EqualizerState copyWith({
    bool? enabled,
    String? presetId,
    double? preampDb,
    bool? limiterEnabled,
    List<double>? bandGainsDb,
    String? rustCrate,
    String? engine,
    String? arch,
  }) {
    return EqualizerState(
      enabled: enabled ?? this.enabled,
      presetId: presetId ?? this.presetId,
      preampDb: preampDb ?? this.preampDb,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      bandGainsDb: bandGainsDb ?? this.bandGainsDb,
      rustCrate: rustCrate ?? this.rustCrate,
      engine: engine ?? this.engine,
      arch: arch ?? this.arch,
    );
  }

  factory EqualizerState.fromMap(Map<String, dynamic> map) {
    final rawBands = map['bandGainsDb'];
    final parsedBands = List<double>.filled(5, 0.0);
    if (rawBands is List) {
      for (var i = 0; i < 5 && i < rawBands.length; i++) {
        parsedBands[i] =
            ((rawBands[i] as num?)?.toDouble() ?? 0.0).clamp(-12.0, 12.0);
      }
    }
    return EqualizerState(
      enabled: map['enabled'] == true,
      presetId: (map['presetId'] ?? 'flat').toString(),
      preampDb:
          ((map['preampDb'] as num?)?.toDouble() ?? 0.0).clamp(-6.0, 6.0),
      limiterEnabled: map['limiterEnabled'] != false,
      bandGainsDb: parsedBands,
      rustCrate: (map['rustCrate'] ?? 'aura_dsp').toString(),
      engine:
          (map['engine'] ?? 'Biquad IIR 5-band + 8D Orbital + Soft Limiter')
              .toString(),
      arch: (map['arch'] ?? '').toString(),
    );
  }
}

enum Spatial8dOutputMode { auto, headphones, speaker }

@immutable
class Spatial8dState {
  const Spatial8dState({
    this.enabled = false,
    this.mode = Spatial8dOutputMode.auto,
    this.resolvedOutput = 'speaker',
    this.speedHz = 0.16,
    this.intensity = 0.75,
    this.rustCrate = 'aura_dsp',
    this.arch = '',
  });

  final bool enabled;
  final Spatial8dOutputMode mode;
  final String resolvedOutput;
  final double speedHz;
  final double intensity;
  final String rustCrate;
  final String arch;

  bool get isHeadphonesActive => resolvedOutput == 'headphones';

  double get orbitSeconds => 1.0 / speedHz.clamp(0.05, 0.50);

  String get modeWireValue => mode.name;

  Spatial8dState copyWith({
    bool? enabled,
    Spatial8dOutputMode? mode,
    String? resolvedOutput,
    double? speedHz,
    double? intensity,
    String? rustCrate,
    String? arch,
  }) {
    return Spatial8dState(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      resolvedOutput: resolvedOutput ?? this.resolvedOutput,
      speedHz: speedHz ?? this.speedHz,
      intensity: intensity ?? this.intensity,
      rustCrate: rustCrate ?? this.rustCrate,
      arch: arch ?? this.arch,
    );
  }

  factory Spatial8dState.fromMap(Map<String, dynamic> map) {
    final rawMode = (map['mode'] ?? 'auto').toString();
    final mode = switch (rawMode) {
      'headphones' => Spatial8dOutputMode.headphones,
      'speaker' => Spatial8dOutputMode.speaker,
      _ => Spatial8dOutputMode.auto,
    };
    return Spatial8dState(
      enabled: map['enabled'] == true,
      mode: mode,
      resolvedOutput:
          (map['resolvedOutput'] ?? 'speaker').toString() == 'headphones'
              ? 'headphones'
              : 'speaker',
      speedHz:
          ((map['speedHz'] as num?)?.toDouble() ?? 0.16).clamp(0.05, 0.50),
      intensity:
          ((map['intensity'] as num?)?.toDouble() ?? 0.75).clamp(0.0, 1.0),
      rustCrate: (map['rustCrate'] ?? 'aura_dsp').toString(),
      arch: (map['arch'] ?? '').toString(),
    );
  }
}

@immutable
class ExploreCategory {
  const ExploreCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.query,
  });

  final String id;
  final String title;
  final String subtitle;
  final String query;
}

@immutable
class ExploreTrackItem {
  const ExploreTrackItem({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.thumbnailUrl,
    required this.webpageUrl,
    this.viewCount = 0,
    this.cachedBytes = 0,
    this.resolvedMimeType = '',
    this.resolvedBitrateKbps = 0,
    this.resolvedSampleRateHz = 0,
  });

  final String videoId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String thumbnailUrl;
  final String webpageUrl;
  final int viewCount;
  final int cachedBytes;
  final String resolvedMimeType;
  final int resolvedBitrateKbps;
  final int resolvedSampleRateHz;

  String get trackId => 'yt_$videoId';
  Duration get duration => Duration(milliseconds: durationMs);
  bool get hasCachedChunks => cachedBytes > 0;

  AudioTrack toStreamTrack() {
    final streamUri = Uri(
      scheme: 'aura-stream',
      host: 'track',
      queryParameters: {
        'id': videoId,
        'u': webpageUrl,
      },
    ).toString();

    return AudioTrack(
      id: trackId,
      uri: streamUri,
      title: title,
      artist: artist,
      album: album,
      folderName: 'Explorar · Streaming',
      durationMs: durationMs,
      mimeType: resolvedMimeType.isNotEmpty ? resolvedMimeType : 'audio/stream',
      bitrateKbps: resolvedBitrateKbps,
      sampleRateHz: resolvedSampleRateHz,
      artworkPath: thumbnailUrl.isNotEmpty ? thumbnailUrl : null,
      sourceUrl: webpageUrl,
    );
  }

  ExploreTrackItem copyWith({
    int? cachedBytes,
    String? resolvedMimeType,
    int? resolvedBitrateKbps,
    int? resolvedSampleRateHz,
    int? durationMs,
  }) {
    return ExploreTrackItem(
      videoId: videoId,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs ?? this.durationMs,
      thumbnailUrl: thumbnailUrl,
      webpageUrl: webpageUrl,
      viewCount: viewCount,
      cachedBytes: cachedBytes ?? this.cachedBytes,
      resolvedMimeType: resolvedMimeType ?? this.resolvedMimeType,
      resolvedBitrateKbps: resolvedBitrateKbps ?? this.resolvedBitrateKbps,
      resolvedSampleRateHz: resolvedSampleRateHz ?? this.resolvedSampleRateHz,
    );
  }

  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'thumbnailUrl': thumbnailUrl,
        'webpageUrl': webpageUrl,
        'viewCount': viewCount,
        'cachedBytes': cachedBytes,
        'resolvedMimeType': resolvedMimeType,
        'resolvedBitrateKbps': resolvedBitrateKbps,
        'resolvedSampleRateHz': resolvedSampleRateHz,
      };

  factory ExploreTrackItem.fromMap(Map<String, dynamic> map) {
    return ExploreTrackItem(
      videoId: (map['videoId'] ?? '').toString(),
      title: (map['title'] ?? 'Pista en streaming').toString(),
      artist: (map['artist'] ?? 'Artista desconocido').toString(),
      album: (map['album'] ?? 'Explorar Aura').toString(),
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      thumbnailUrl: (map['thumbnailUrl'] ?? '').toString(),
      webpageUrl: (map['webpageUrl'] ?? '').toString(),
      viewCount: (map['viewCount'] as num?)?.toInt() ?? 0,
      cachedBytes: (map['cachedBytes'] as num?)?.toInt() ?? 0,
      resolvedMimeType: (map['resolvedMimeType'] ?? '').toString(),
      resolvedBitrateKbps:
          (map['resolvedBitrateKbps'] as num?)?.toInt() ?? 0,
      resolvedSampleRateHz:
          (map['resolvedSampleRateHz'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ExploreSearchResult {
  const ExploreSearchResult({
    required this.query,
    required this.items,
  });

  final String query;
  final List<ExploreTrackItem> items;
}

@immutable
class ExploreSignalRecord {
  const ExploreSignalRecord({
    required this.videoId,
    required this.title,
    required this.artist,
    this.webpageUrl = '',
    this.thumbnailUrl = '',
    this.durationMs = 0,
    this.playCount = 0,
    this.completeCount = 0,
    this.skipCount = 0,
    this.queueCount = 0,
    this.downloaded = false,
    this.lastInteractedAtMs = 0,
  });

  final String videoId;
  final String title;
  final String artist;
  final String webpageUrl;
  final String thumbnailUrl;
  final int durationMs;
  final int playCount;
  final int completeCount;
  final int skipCount;
  final int queueCount;
  final bool downloaded;
  final int lastInteractedAtMs;

  factory ExploreSignalRecord.fromMap(Map<String, dynamic> map) {
    return ExploreSignalRecord(
      videoId: (map['videoId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      artist: (map['artist'] ?? '').toString(),
      webpageUrl: (map['webpageUrl'] ?? '').toString(),
      thumbnailUrl: (map['thumbnailUrl'] ?? '').toString(),
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      playCount: (map['playCount'] as num?)?.toInt() ?? 0,
      completeCount: (map['completeCount'] as num?)?.toInt() ?? 0,
      skipCount: (map['skipCount'] as num?)?.toInt() ?? 0,
      queueCount: (map['queueCount'] as num?)?.toInt() ?? 0,
      downloaded: (map['downloaded'] == true) || (map['downloaded'] == 1),
      lastInteractedAtMs:
          (map['lastInteractedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ExplorePersonalizedFeed {
  const ExplorePersonalizedFeed({
    this.forYou = const [],
    this.becauseLabel = '',
    this.becauseItems = const [],
    this.discoveryItems = const [],
    this.resolvedSeeds = const {},
    this.generatedAtMs = 0,
    this.isColdStart = false,
  });

  final List<ExploreTrackItem> forYou;
  final String becauseLabel;
  final List<ExploreTrackItem> becauseItems;
  final List<ExploreTrackItem> discoveryItems;
  final Map<String, String> resolvedSeeds;
  final int generatedAtMs;
  final bool isColdStart;

  bool get isEmpty =>
      forYou.isEmpty && becauseItems.isEmpty && discoveryItems.isEmpty;

  ExplorePersonalizedFeed copyWith({
    List<ExploreTrackItem>? forYou,
    String? becauseLabel,
    List<ExploreTrackItem>? becauseItems,
    List<ExploreTrackItem>? discoveryItems,
    Map<String, String>? resolvedSeeds,
    int? generatedAtMs,
    bool? isColdStart,
  }) {
    return ExplorePersonalizedFeed(
      forYou: forYou ?? this.forYou,
      becauseLabel: becauseLabel ?? this.becauseLabel,
      becauseItems: becauseItems ?? this.becauseItems,
      discoveryItems: discoveryItems ?? this.discoveryItems,
      resolvedSeeds: resolvedSeeds ?? this.resolvedSeeds,
      generatedAtMs: generatedAtMs ?? this.generatedAtMs,
      isColdStart: isColdStart ?? this.isColdStart,
    );
  }

  Map<String, dynamic> toMap() => {
        'forYou': forYou.map((e) => e.toMap()).toList(),
        'becauseLabel': becauseLabel,
        'becauseItems': becauseItems.map((e) => e.toMap()).toList(),
        'discoveryItems': discoveryItems.map((e) => e.toMap()).toList(),
        'generatedAtMs': generatedAtMs,
        'isColdStart': isColdStart,
      };

  static List<ExploreTrackItem> _parseItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => ExploreTrackItem.fromMap(Map<String, dynamic>.from(m)))
        .where((item) => item.videoId.isNotEmpty)
        .toList();
  }

  factory ExplorePersonalizedFeed.fromMap(Map<String, dynamic> map) {
    final rawSeeds = map['resolvedSeeds'];
    final seedsMap = <String, String>{};
    if (rawSeeds is List) {
      for (final entry in rawSeeds) {
        if (entry is Map) {
          final tid = (entry['trackId'] ?? '').toString();
          final vid = (entry['videoId'] ?? '').toString();
          if (tid.isNotEmpty && vid.isNotEmpty) {
            seedsMap[tid] = vid;
          }
        }
      }
    }
    return ExplorePersonalizedFeed(
      forYou: _parseItems(map['forYou']),
      becauseLabel: (map['becauseLabel'] ?? '').toString(),
      becauseItems: _parseItems(map['becauseItems']),
      discoveryItems: _parseItems(map['discoveryItems']),
      resolvedSeeds: seedsMap,
      generatedAtMs: (map['generatedAtMs'] as num?)?.toInt() ?? 0,
      isColdStart: map['isColdStart'] == true,
    );
  }
}

@immutable
class ResolvedStreamInfo {
  const ResolvedStreamInfo({
    required this.videoId,
    required this.webpageUrl,
    required this.mimeType,
    required this.ext,
    required this.abr,
    required this.asr,
    required this.durationMs,
    required this.expiresAtMs,
    required this.cachedBytes,
  });

  final String videoId;
  final String webpageUrl;
  final String mimeType;
  final String ext;
  final int abr;
  final int asr;
  final int durationMs;
  final int expiresAtMs;
  final int cachedBytes;

  factory ResolvedStreamInfo.fromMap(Map<String, dynamic> map) {
    return ResolvedStreamInfo(
      videoId: (map['videoId'] ?? '').toString(),
      webpageUrl: (map['webpageUrl'] ?? '').toString(),
      mimeType: (map['mimeType'] ?? 'audio/mp4').toString(),
      ext: (map['ext'] ?? 'm4a').toString(),
      abr: (map['abr'] as num?)?.toInt() ?? 0,
      asr: (map['asr'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      expiresAtMs: (map['expiresAtMs'] as num?)?.toInt() ?? 0,
      cachedBytes: (map['cachedBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class StreamCacheStats {
  const StreamCacheStats({
    this.usedBytes = 0,
    this.maxBytes = 512 * 1024 * 1024,
    this.cachedTracks = 0,
  });

  final int usedBytes;
  final int maxBytes;
  final int cachedTracks;

  String get formattedUsed {
    if (usedBytes <= 0) return '0 MB';
    if (usedBytes < 1024 * 1024) {
      return '${(usedBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(usedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory StreamCacheStats.fromMap(Map<String, dynamic> map) {
    return StreamCacheStats(
      usedBytes: (map['usedBytes'] as num?)?.toInt() ?? 0,
      maxBytes: (map['maxBytes'] as num?)?.toInt() ?? 512 * 1024 * 1024,
      cachedTracks: (map['cachedTracks'] as num?)?.toInt() ?? 0,
    );
  }
}


