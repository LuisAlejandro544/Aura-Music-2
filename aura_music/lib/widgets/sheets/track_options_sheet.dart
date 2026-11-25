// =============================================================================
// track_options_sheet.dart — Popup de acciones contextuales por canción
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Abre un menú inferior elegante para reproducir a continuación, encolar,
//   guardar en playlist local, inspeccionar ficha técnica del archivo (codec,
//   bitrate, motor ExoPlayer) o quitar la referencia de la biblioteca.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/audio_track.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../artwork_view.dart';

Future<void> showTrackOptionsSheet(BuildContext context, AudioTrack track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TrackOptionsSheet(track: track),
  );
}

class _TrackOptionsSheet extends StatelessWidget {
  const _TrackOptionsSheet({required this.track});

  final AudioTrack track;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.read<PlayerProvider>();
    final liveTrack = library.findById(track.id) ?? track;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4.5,
              decoration: BoxDecoration(
                color: AuraColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ArtworkView(
                  artworkPath: liveTrack.artworkPath,
                  seed: '${liveTrack.album}_${liveTrack.title}',
                  size: 54,
                  borderRadius: 14,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        liveTrack.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AuraColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${liveTrack.artist} · ${liveTrack.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AuraColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: AuraColors.border, height: 1),
            const SizedBox(height: 6),
            _SheetActionRow(
              icon: liveTrack.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: liveTrack.isFavorite ? AuraColors.accent : null,
              label: liveTrack.isFavorite
                  ? 'Quitar de favoritos'
                  : 'Agregar a favoritos',
              onTap: () {
                library.toggleFavorite(liveTrack.id);
                Navigator.pop(context);
              },
            ),
            _SheetActionRow(
              icon: Icons.playlist_play_rounded,
              label: 'Reproducir siguiente',
              onTap: () {
                player.playNextInQueue(liveTrack);
                Navigator.pop(context);
              },
            ),
            _SheetActionRow(
              icon: Icons.queue_music_rounded,
              label: 'Añadir a la cola',
              onTap: () {
                player.addToQueueEnd(liveTrack);
                Navigator.pop(context);
              },
            ),
            _SheetActionRow(
              icon: Icons.playlist_add_rounded,
              label: 'Guardar en una playlist',
              onTap: () {
                Navigator.pop(context);
                _showPlaylistPicker(context, liveTrack);
              },
            ),
            _SheetActionRow(
              icon: Icons.graphic_eq_rounded,
              label: 'Ficha técnica (${liveTrack.technicalSummary})',
              onTap: () {
                Navigator.pop(context);
                _showTechnicalPopup(context, liveTrack);
              },
            ),
            _SheetActionRow(
              icon: Icons.delete_outline_rounded,
              color: const Color(0xFFB44437),
              label: 'Quitar de Aura Music',
              onTap: () {
                library.removeTrack(liveTrack.id);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistPicker(BuildContext context, AudioTrack target) {
    final library = context.read<LibraryProvider>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final playlists = library.playlists;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Añadir a playlist',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AuraColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Todavía no tienes playlists. Crea una en la pestaña Biblioteca.',
                      style: TextStyle(color: AuraColors.textSecondary),
                    ),
                  )
                else
                  ...playlists.map(
                    (pl) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.queue_music_rounded,
                        color: AuraColors.accent,
                      ),
                      title: Text(
                        pl.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${pl.tracks.length} canciones'),
                      onTap: () async {
                        await library.addTrackToPlaylist(pl.id, target.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTechnicalPopup(BuildContext context, AudioTrack target) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AuraColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Detalles de audio local',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow('Formato', target.formatBadge),
            _DetailRow(
              'Bitrate',
              target.bitrateKbps > 0 ? '${target.bitrateKbps} kbps' : 'Variable',
            ),
            _DetailRow(
              'Frecuencia',
              target.sampleRateHz > 0
                  ? '${(target.sampleRateHz / 1000).toStringAsFixed(1)} kHz'
                  : 'Estándar',
            ),
            _DetailRow('Carpeta', target.folderName),
            _DetailRow('Motor activo', 'Media3 ExoPlayer (Android 9+)'),
            _DetailRow('Módulo DSP', 'Arquitectura lista para Rust'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  const _SheetActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: color ?? AuraColors.textPrimary),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: color ?? AuraColors.textPrimary,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: AuraColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AuraColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
