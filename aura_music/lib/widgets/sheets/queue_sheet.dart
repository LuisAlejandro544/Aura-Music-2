// =============================================================================
// queue_sheet.dart — Popup de cola de reproducción activa
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Muestra las canciones cargadas actualmente en ExoPlayer, resalta la pista
//   en curso y permite saltar instantáneamente a cualquier tema de la cola.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/aura_theme.dart';
import '../../state/player_provider.dart';
import '../artwork_view.dart';

Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4.5,
              decoration: BoxDecoration(
                color: AuraColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  const Text(
                    'Cola de reproducción',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AuraColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AuraColors.surface,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${queue.length} pistas',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AuraColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AuraColors.border, height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: queue.length,
                itemBuilder: (context, index) {
                  final item = queue[index];
                  final isCurrent = index == player.currentIndex;

                  return ListTile(
                    onTap: () => player.jumpToQueueIndex(index),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: isCurrent
                        ? AuraColors.accentSoft.withValues(alpha: 0.7)
                        : null,
                    leading: ArtworkView(
                      artworkPath: item.artworkPath,
                      seed: '${item.album}_${item.title}',
                      size: 46,
                      borderRadius: 11,
                    ),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                        color: isCurrent
                            ? AuraColors.accent
                            : AuraColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      item.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AuraColors.textSecondary),
                    ),
                    trailing: isCurrent
                        ? const Icon(
                            Icons.graphic_eq_rounded,
                            color: AuraColors.accent,
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
