import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../../playback/linux_install_kind.dart';
import 'player_center_panel.dart';

const _maxRecentRows = 5;

class PlayerEmptyState extends StatelessWidget {
  const PlayerEmptyState({
    super.key,
    required this.tipDismissed,
    required this.onDismissTip,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenPlaylist,
    required this.onOpenUrl,
    required this.onReopenLast,
    this.recentFiles = const [],
    this.onOpenRecent,
  });

  final bool tipDismissed;
  final VoidCallback onDismissTip;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenPlaylist;
  final VoidCallback onOpenUrl;
  final VoidCallback onReopenLast;
  final List<String> recentFiles;
  final ValueChanged<String>? onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final flatpak = LinuxInstallDetector.isFlatpak;
    final recents = recentFiles.take(_maxRecentRows).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: PlayerCenterPanel(
                maxWidth: 440,
                outerPadding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 24,
                  vertical: compact ? 12 : 24,
                ),
                panelPadding: compact
                    ? const EdgeInsets.fromLTRB(24, 20, 24, 20)
                    : const EdgeInsets.fromLTRB(32, 34, 32, 38),
                children: [
                  PlayerCenterIconSurface(
                    icon: Icons.music_note,
                    size: 40,
                    diameter: compact ? 72 : 132,
                    color: colorScheme.primary.withValues(alpha: 0.88),
                  ),
                  SizedBox(height: compact ? 12 : 20),
                  Text(
                    flatpak
                        ? l10n.emptyStateFlatpakMessage
                        : l10n.emptyStateMessage,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.74),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: compact ? 16 : 24),
                  FilledButton.icon(
                    key: const Key('open-file-empty-button'),
                    onPressed: onOpenFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.buttonOpenFile),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        key: const Key('open-folder-empty-button'),
                        onPressed: onOpenFolder,
                        icon: const Icon(Icons.create_new_folder),
                        label: Text(l10n.buttonOpenFolder),
                      ),
                      TextButton.icon(
                        key: const Key('open-playlist-empty-button'),
                        onPressed: onOpenPlaylist,
                        icon: const Icon(Icons.queue_music),
                        label: Text(l10n.buttonOpenPlaylist),
                      ),
                      TextButton.icon(
                        key: const Key('open-url-empty-button'),
                        onPressed: onOpenUrl,
                        icon: const Icon(Icons.link),
                        label: Text(l10n.buttonOpenUrl),
                      ),
                      if (recents.isNotEmpty)
                        TextButton.icon(
                          key: const Key('reopen-last-empty-button'),
                          onPressed: onReopenLast,
                          icon: const Icon(Icons.history),
                          label: Text(l10n.buttonReopenLast),
                        ),
                    ],
                  ),
                  if (recents.isNotEmpty) ...[
                    SizedBox(height: compact ? 12 : 20),
                    Text(
                      l10n.emptyStateRecentTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (var i = 0; i < recents.length; i++)
                      Tooltip(
                        message: recents[i],
                        child: TextButton(
                          key: Key('empty-recent-$i'),
                          onPressed: onOpenRecent == null
                              ? null
                              : () => onOpenRecent!(recents[i]),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: colorScheme.onSurface.withValues(
                              alpha: 0.74,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.music_note, size: 16),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  p.basename(recents[i]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (!tipDismissed) ...[
                    SizedBox(height: compact ? 12 : 20),
                    Text(
                      l10n.emptyStateTipReopenLast,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.58),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      key: const Key('empty-state-tip-dismiss'),
                      onPressed: onDismissTip,
                      child: Text(l10n.actionDismissTip),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
