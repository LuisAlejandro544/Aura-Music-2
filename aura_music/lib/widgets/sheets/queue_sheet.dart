// =============================================================================
// queue_sheet.dart — Popup de cola de reproducción activa
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Muestra las canciones cargadas actualmente en ExoPlayer, resalta la pista
//   en curso y permite saltar instantáneamente a cualquier tema de la cola.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final c = AuraTheme.of(context);
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
                color: c.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cola de reproducción',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Arrastra para ordenar o toca para saltar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${queue.length} pistas',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: c.border, height: 1),
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Text(
                        'La cola está vacía',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollController: scrollController,
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: queue.length,
                      onReorder: (oldIndex, newIndex) {
                        HapticFeedback.selectionClick();
                        var targetIndex = newIndex;
                        if (targetIndex > oldIndex) {
                          targetIndex -= 1;
                        }
                        player.reorderQueueItem(oldIndex, targetIndex);
                      },
                      itemBuilder: (context, index) {
                        final item = queue[index];
                        final isCurrent = index == player.currentIndex;

                        return Material(
                          key: ObjectKey(item),
                          color: Colors.transparent,
                          child: ListTile(
                            onTap: () => player.jumpToQueueIndex(index),
                            contentPadding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            tileColor: isCurrent
                                ? c.accentSoft.withValues(alpha: 0.7)
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
                                color: isCurrent ? c.accent : c.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              item.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrent)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.graphic_eq_rounded,
                                      size: 20,
                                      color: c.accent,
                                    ),
                                  ),
                                IconButton(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    player.removeFromQueue(index);
                                  },
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 19,
                                    color: c.textSecondary,
                                  ),
                                  tooltip: 'Quitar de la cola',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      size: 20,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
