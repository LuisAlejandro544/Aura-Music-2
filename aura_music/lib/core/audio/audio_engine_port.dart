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

  Future<YtEngineStatus> getYtEngineStatus();

  /// Control de cola y reproducción
  Future<void> setQueueAndPlay({
    required List<AudioTrack> tracks,
    required int startIndex,
    bool autoPlay = true,
    int startPositionMs = 0,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> skipToIndex(int index);
  Future<void> setShuffle(bool enabled);
  Future<void> setAuraRepeatMode(AuraRepeatMode mode);

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

  Future<void> updateMediaItemMetadata(AudioTrack track);

  void dispose();
}
