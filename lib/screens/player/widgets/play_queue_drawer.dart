import 'package:flutter/material.dart';

import '../../../models/playable_source.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/playlist_service.dart';
import '../../../theme/glass_decorations.dart';
import '../../../widgets/queue_item_tile.dart';

Future<bool?> showClearQueueConfirmation(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final dialogL10n = AppLocalizations.of(ctx);
      return AlertDialog(
        title: Text(dialogL10n.dialogClearQueueTitle),
        content: Text(dialogL10n.dialogClearQueueBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(dialogL10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(dialogL10n.actionClear),
          ),
        ],
      );
    },
  );
}

class PlayQueueDrawer extends StatelessWidget {
  const PlayQueueDrawer({
    super.key,
    required this.playlist,
    required this.hasCurrentFile,
    required this.onShowMediaInfo,
    required this.onSetShuffle,
    required this.onClearQueue,
    required this.onActivateItem,
    required this.onRemoveItem,
    required this.onAddFiles,
    required this.onAddFolder,
    required this.onOpenPlaylist,
    required this.onSavePlaylist,
    required this.onRemoveMissing,
  });

  final PlaylistService playlist;
  final bool Function() hasCurrentFile;
  final VoidCallback onShowMediaInfo;
  final ValueChanged<bool> onSetShuffle;
  final VoidCallback onClearQueue;
  final ValueChanged<PlayableSource> onActivateItem;
  final ValueChanged<int> onRemoveItem;
  final VoidCallback onAddFiles;
  final ValueChanged<bool> onAddFolder;
  final ValueChanged<bool> onOpenPlaylist;
  final VoidCallback onSavePlaylist;
  final VoidCallback onRemoveMissing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: FocusScope(
        child: GlassDrawerBody(
          child: SafeArea(
            child: ListenableBuilder(
              listenable: playlist,
              builder: (context, _) {
                final items = playlist.items;
                return Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                      child: Row(
                        children: [
                          Icon(Icons.queue_music, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.dialogPlayQueueTitle,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.info_outline),
                            tooltip: l10n.tooltipMediaInfo,
                            onPressed: !hasCurrentFile()
                                ? null
                                : onShowMediaInfo,
                          ),
                          if (items.isNotEmpty)
                            IconButton(
                              icon: Icon(
                                playlist.shuffle
                                    ? Icons.shuffle_on
                                    : Icons.shuffle,
                              ),
                              tooltip: l10n.tooltipShuffle,
                              onPressed: () {
                                onSetShuffle(!playlist.shuffle);
                              },
                            ),
                          if (items.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_all),
                              tooltip: l10n.actionClear,
                              onPressed: onClearQueue,
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // List
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Text(
                                l10n.dialogPlayQueueEmpty,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.54,
                                  ),
                                ),
                              ),
                            )
                          : Semantics(
                              label: l10n.queueReorderSemantic,
                              child: ReorderableListView.builder(
                                buildDefaultDragHandles: false,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: items.length,
                                onReorderItem: playlist.moveItem,
                                itemBuilder: (context, index) {
                                  final isCurrent = index == playlist.index;
                                  final source = items[index];
                                  final name = source.displayName;

                                  return QueueItemTile(
                                    key: ValueKey(
                                      'queue-$index-${source.value}',
                                    ),
                                    name: name,
                                    isCurrent: isCurrent,
                                    isUrl: source.isUrl,
                                    playLabel: l10n.actionPlay,
                                    removeLabel: l10n.actionRemove,
                                    reorderLabel: l10n.queueReorderSemantic,
                                    reorderIndex: index,
                                    colorScheme: colorScheme,
                                    onActivate: () {
                                      playlist.jumpTo(index);
                                      onActivateItem(source);
                                    },
                                    onRemove: () {
                                      onRemoveItem(index);
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                    const Divider(height: 1),
                    // Actions at bottom
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: onAddFiles,
                            icon: const Icon(Icons.add),
                            label: Text(l10n.dialogPlayQueueAddFiles),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('queue-add-folder-button'),
                            onPressed: () => onAddFolder(playlist.isEmpty),
                            icon: const Icon(Icons.create_new_folder),
                            label: Text(l10n.buttonOpenFolder),
                          ),
                          FilledButton.tonalIcon(
                            key: const Key('queue-open-playlist-button'),
                            onPressed: () => onOpenPlaylist(playlist.isEmpty),
                            icon: const Icon(Icons.queue_music),
                            label: Text(l10n.buttonOpenPlaylist),
                          ),
                          if (items.isNotEmpty)
                            FilledButton.tonalIcon(
                              key: const Key('queue-save-playlist-button'),
                              onPressed: onSavePlaylist,
                              icon: const Icon(Icons.save_alt),
                              label: Text(l10n.buttonSavePlaylist),
                            ),
                          if (items.isNotEmpty)
                            FilledButton.tonalIcon(
                              key: const Key('queue-remove-missing-button'),
                              onPressed: onRemoveMissing,
                              icon: const Icon(Icons.cleaning_services),
                              label: Text(l10n.actionRemoveMissing),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
