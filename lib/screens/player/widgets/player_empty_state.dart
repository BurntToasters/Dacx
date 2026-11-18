import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../playback/linux_install_kind.dart';
import 'player_center_panel.dart';

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
  });

  final bool tipDismissed;
  final VoidCallback onDismissTip;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenPlaylist;
  final VoidCallback onOpenUrl;
  final VoidCallback onReopenLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final flatpak = LinuxInstallDetector.isFlatpak;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: PlayerCenterPanel(
                maxWidth: 440,
                children: [
                  PlayerCenterIconSurface(
                    icon: Icons.music_note,
                    size: 40,
                    color: colorScheme.primary.withValues(alpha: 0.88),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    flatpak
                        ? l10n.emptyStateFlatpakMessage
                        : l10n.emptyStateMessage,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.74),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!tipDismissed) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.emptyStateTipReopenLast,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: onOpenFile,
                        icon: const Icon(Icons.folder_open),
                        label: Text(l10n.buttonOpenFile),
                      ),
                      FilledButton.tonalIcon(
                        key: const Key('open-folder-empty-button'),
                        onPressed: onOpenFolder,
                        icon: const Icon(Icons.create_new_folder),
                        label: Text(l10n.buttonOpenFolder),
                      ),
                      FilledButton.tonalIcon(
                        key: const Key('open-playlist-empty-button'),
                        onPressed: onOpenPlaylist,
                        icon: const Icon(Icons.queue_music),
                        label: Text(l10n.buttonOpenPlaylist),
                      ),
                      FilledButton.tonalIcon(
                        key: const Key('open-url-empty-button'),
                        onPressed: onOpenUrl,
                        icon: const Icon(Icons.link),
                        label: Text(l10n.buttonOpenUrl),
                      ),
                      FilledButton.tonalIcon(
                        key: const Key('reopen-last-empty-button'),
                        onPressed: onReopenLast,
                        icon: const Icon(Icons.history),
                        label: Text(l10n.buttonReopenLast),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
