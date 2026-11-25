// =============================================================================
// audio_engine_port.dart — Puerto abstracto del motor de audio
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Desacopla toda la interfaz y lógica de estado de Aura Music respecto al
//   motor concreto que decodifica y reproduce el audio.
//   - Hoy: ExoPlayerBridge (Media3 ExoPlayer en Kotlin).
//   - Futuro (última versión): permitirá acoplar el módulo nativo en Rust
//     (ecualizador paramétrico, replay-gain, análisis espectral, DSP) sin
//     modificar las pantallas ni los gestos de Flutter.
// =============================================================================

import 'dart:async';
import '../models/audio_track.dart';

abstract class AudioEnginePort {
  AudioEngineBackend get activeBackend;

  Stream<NativePlaybackEvent> get playbackEvents;
  Stream<({int processed, int total})> get importProgressEvents;
  Stream<DownloadProgressEvent> get downloadProgressEvents;
  Stream<YtUpdateProgressEvent> get ytUpdateProgressEvents;
  Stream<Spatial8dState> get spatial8dEvents;
  Stream<String> get errorEvents;

  Future<void> initialize();

  /// Importación manual vía Storage Access Framework (sin escanear el teléfono)
  Future<List<AudioTrack>> pickAudioFiles();
  Future<List<AudioTrack>> pickAudioFolder();

  /// Descarga directa desde URL con yt-dlp + yt-dlp-ejs + Rust QuickJS-ng
  Future<AudioTrack> downloadFromUrl({
    required String url,
    YtDownloadFormat format = YtDownloadFormat.best,
  });

  /// Explorar y streaming progresivo con yt-dlp + Media3 SimpleCache
  Future<ExploreSearchResult> searchExplore({
    required String query,
    int limit = 18,
  });

  Future<ResolvedStreamInfo> resolveExploreStream({
    required String url,
    String videoId = '',
    YtDownloadFormat format = YtDownloadFormat.best,
  });

  Future<StreamCacheStats> getStreamCacheStats();
  Future<StreamCacheStats> clearStreamCache();

  Future<YtEngineStatus> getYtEngineStatus({bool includePython = false});
  Future<YtUpdateCheckResult> checkYtEngineUpdates();
  Future<YtUpdateResult> updateYtEngine({bool force = false});
  Future<bool> setYtAutoUpdateEnabled(bool enabled);
  Future<YtRestoreResult> restoreBundledYtEngine();


  /// Control de cola y reproducción
  Future<void> setQueueAndPlay({
    required List<AudioTrack> tracks,
    required int startIndex,
    bool autoPlay = true,
    int startPositionMs = 0,
  });

  Future<void> addToQueue({
    required AudioTrack track,
    int? insertIndex,
  });

  Future<void> moveQueueItem({
    required int fromIndex,
    required int toIndex,
  });

  Future<void> removeQueueItem({required int index});

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> skipToIndex(int index);
  Future<void> setShuffle(bool enabled);
  Future<void> setAuraRepeatMode(AuraRepeatMode mode);

  /// Ecualizador / DSP nativo en Rust (`aura_dsp`)
  Future<EqualizerState> getEqualizerState();

  Future<EqualizerState> updateEqualizerState(EqualizerState state);

  /// Procesador Audio 8D orbital en Rust (`aura_dsp`)
  Future<Spatial8dState> getSpatial8dState();

  Future<Spatial8dState> updateSpatial8dState(Spatial8dState state);

  /// Conversión nativa a WebP sin pérdida y actualización de metadatos en cola
  Future<LosslessWebpResult> convertImageToLosslessWebp({
    required String sourcePath,
    required String trackId,
  });

  Future<String> commitCustomArtwork({
    required String pendingPath,
    required String trackId,
  });

  Future<void> deleteCustomArtworks(String trackId);

  Future<void> deleteTrackResources({
    required String trackId,
    required String trackUri,
  });

  Future<void> updateMediaItemMetadata(AudioTrack track);

  void dispose();
}
