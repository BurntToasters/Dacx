import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/playable_source.dart';
import '../services/settings_service.dart';

class TransportControls extends StatelessWidget {
  final bool isPlaying;
  final double volume;
  final bool hasMedia;
  final double speed;
  final LoopMode loopMode;
  final List<String> recentFiles;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onOpenFile;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onOpenUrl;
  final VoidCallback onReopenLast;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<LoopMode> onLoopModeChanged;
  final ValueChanged<String> onRecentFileSelected;
  final VoidCallback onSettingsPressed;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToggleQueue;
  final VoidCallback? onMoreActions;

  const TransportControls({
    super.key,
    required this.isPlaying,
    required this.volume,
    required this.hasMedia,
    required this.speed,
    required this.loopMode,
    required this.recentFiles,
    required this.onPlayPause,
    required this.onStop,
    required this.onOpenFile,
    this.onOpenFolder,
    this.onOpenUrl,
    required this.onReopenLast,
    required this.onVolumeChanged,
    required this.onLoopModeChanged,
    required this.onRecentFileSelected,
    required this.onSettingsPressed,
    this.onPrevious,
    this.onNext,
    this.onToggleQueue,
    this.onMoreActions,
  });

  void _cycleLoopMode() {
    final next = switch (loopMode) {
      LoopMode.none => LoopMode.loop,
      LoopMode.loop => LoopMode.single,
      LoopMode.single => LoopMode.none,
    };
    onLoopModeChanged(next);
  }

  IconData get _loopIcon => switch (loopMode) {
    LoopMode.none => Icons.repeat,
    LoopMode.loop => Icons.repeat_on,
    LoopMode.single => Icons.repeat_one_on,
  };

  String _loopTooltip(AppLocalizations l10n) => switch (loopMode) {
    LoopMode.none => l10n.loopOff,
    LoopMode.loop => l10n.loopAll,
    LoopMode.single => l10n.loopSingle,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showVolumeSlider = screenWidth > 580;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        children: [
          // Left side: File opening and history
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildOpenButton(context, l10n),
                IconButton(
                  key: const Key('reopen-last-transport-button'),
                  icon: const Icon(Icons.history),
                  tooltip: l10n.tooltipReopenLast,
                  onPressed: onReopenLast,
                ),
              ],
            ),
          ),

          // Center: Playback control group
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: l10n.tooltipPreviousTrack,
                onPressed: hasMedia ? onPrevious : null,
                iconSize: 22,
              ),
              IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 170),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final scale = Tween<double>(
                      begin: 0.86,
                      end: 1.0,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: scale, child: child),
                    );
                  },
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    key: ValueKey<bool>(isPlaying),
                  ),
                ),
                tooltip: isPlaying ? l10n.actionPause : l10n.actionPlay,
                iconSize: 36,
                onPressed: hasMedia ? onPlayPause : null,
              ),
              IconButton(
                icon: const Icon(Icons.stop),
                tooltip: l10n.tooltipStop,
                onPressed: hasMedia ? onStop : null,
                iconSize: 22,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: l10n.tooltipNextTrack,
                onPressed: hasMedia ? onNext : null,
                iconSize: 22,
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(_loopIcon),
                tooltip: _loopTooltip(l10n),
                onPressed: _cycleLoopMode,
                iconSize: 20,
              ),
              // Speed chip (visible when != 1.0)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SizeTransition(
                      axis: Axis.horizontal,
                      alignment: const Alignment(-1.0, 0.0),
                      sizeFactor: animation,
                      child: child,
                    ),
                  );
                },
                child: speed != 1.0
                    ? Padding(
                        key: ValueKey<double>(speed),
                        padding: const EdgeInsets.only(left: 4),
                        child: Chip(
                          label: Text(
                            '$speed×',
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                    : const SizedBox(key: ValueKey('speed-empty')),
              ),
            ],
          ),

          // Right side: Volume and auxiliary actions
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Semantics(
                  label: volume == 0
                      ? l10n.volumeMuted
                      : l10n.volumePercent(volume.round()),
                  child: Icon(
                    volume == 0 ? Icons.volume_off : Icons.volume_up,
                    size: 20,
                  ),
                ),
                if (showVolumeSlider)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 100,
                      minWidth: 50,
                    ),
                    child: Semantics(
                      slider: true,
                      label: l10n.volumeLabel,
                      value: '${volume.round()}%',
                      child: Slider(
                        value: volume.clamp(0, 100),
                        min: 0,
                        max: 100,
                        divisions: 100,
                        onChanged: onVolumeChanged,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Queue toggle button
                IconButton(
                  icon: const Icon(Icons.queue_music),
                  tooltip: l10n.tooltipPlayQueue,
                  iconSize: 20,
                  onPressed: onToggleQueue,
                ),
                if (onMoreActions != null)
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: l10n.tooltipMore,
                    iconSize: 20,
                    onPressed: hasMedia ? onMoreActions : null,
                  ),
                // Settings gear
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: l10n.tooltipSettings,
                  iconSize: 20,
                  onPressed: onSettingsPressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenButton(BuildContext context, AppLocalizations l10n) {
    final recents = recentFiles
        .where((path) => path.trim().isNotEmpty)
        .take(10)
        .toList(growable: false);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: l10n.tooltipOpenFile,
          onPressed: onOpenFile,
        ),
        if (onOpenFolder != null)
          IconButton(
            key: const Key('open-folder-transport-button'),
            icon: const Icon(Icons.create_new_folder),
            tooltip: l10n.tooltipOpenFolder,
            onPressed: onOpenFolder,
          ),
        if (onOpenUrl != null)
          IconButton(
            key: const Key('open-url-transport-button'),
            icon: const Icon(Icons.link),
            tooltip: l10n.tooltipOpenUrl,
            onPressed: onOpenUrl,
          ),
        if (recents.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: l10n.tooltipRecentFiles,
            position: PopupMenuPosition.over,
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: onRecentFileSelected,
            itemBuilder: (context) => recents.map((path) {
              final source = PlayableSource.fromStored(path);
              final name = source?.displayName ?? p.basename(path).trim();
              return PopupMenuItem<String>(
                key: ValueKey<String>(path),
                value: path,
                child: Text(
                  name.isEmpty ? path : name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
