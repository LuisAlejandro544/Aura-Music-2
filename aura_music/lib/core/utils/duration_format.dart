// =============================================================================
// duration_format.dart — Utilidades de formateo de tiempos y contadores
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Convierte duraciones en milisegundos/Duration al formato mm:ss o h:mm:ss
//   para barras de progreso, mini reproductor y resúmenes de álbumes.
// =============================================================================

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 86400);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final secStr = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final minStr = minutes.toString().padLeft(2, '0');
    return '$hours:$minStr:$secStr';
  }
  return '$minutes:$secStr';
}

String formatCollectionSummary(int trackCount, Duration total) {
  final mins = total.inMinutes;
  final trackLabel = trackCount == 1 ? '1 canción' : '$trackCount canciones';
  if (mins < 60) {
    return '$trackLabel · $mins min';
  }
  final hours = mins ~/ 60;
  final remMins = mins % 60;
  return '$trackLabel · ${hours}h ${remMins}m';
}
