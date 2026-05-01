import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
  final VoidCallback onReopenLast;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<LoopMode> onLoopModeChanged;
  final ValueChanged<String> onRecentFileSelected;
  final VoidCallback onSettingsPressed;

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
    required this.onReopenLast,
    required this.onVolumeChanged,
    required this.onLoopModeChanged,
    required this.onRecentFileSelected,
    required this.onSettingsPressed,
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

  String get _loopTooltip => switch (loopMode) {
    LoopMode.none => 'Loop: Off',
    LoopMode.loop => 'Loop: All',
    LoopMode.single => 'Loop: Single',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        children: [
          // Open button (with recent files popup)
          _buildOpenButton(context),
          IconButton(
            key: const Key('reopen-last-transport-button'),
            icon: const Icon(Icons.history),
            tooltip: 'Reopen last file (Ctrl/Cmd+R)',
            onPressed: onReopenLast,
          ),
          const SizedBox(width: 8),
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
            tooltip: isPlaying ? 'Pause' : 'Play',
            iconSize: 36,
            onPressed: hasMedia ? onPlayPause : null,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            tooltip: 'Stop',
            onPressed: hasMedia ? onStop : null,
          ),
          const SizedBox(width: 4),
          // Loop toggle
          IconButton(
            icon: Icon(_loopIcon),
            tooltip: _loopTooltip,
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
                  axisAlignment: -1,
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
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                : const SizedBox(key: ValueKey('speed-empty')),
          ),
          const Spacer(),
          Semantics(
            label: volume == 0 ? 'Muted' : 'Volume ${volume.round()} percent',
            child: Icon(
              volume == 0 ? Icons.volume_off : Icons.volume_up,
              size: 20,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160, minWidth: 60),
            child: Semantics(
              slider: true,
              label: 'Volume',
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
          // Settings gear
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            iconSize: 20,
            onPressed: onSettingsPressed,
          ),
        ],
      ),
    );
  }

  Widget _buildOpenButton(BuildContext context) {
    final recents = recentFiles
        .where((path) => path.trim().isNotEmpty)
        .take(10)
        .toList(growable: false);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: 'Open file',
          onPressed: onOpenFile,
        ),
        if (recents.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Recent files',
            position: PopupMenuPosition.over,
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: onRecentFileSelected,
            itemBuilder: (context) => recents.map((path) {
              final name = p.basename(path).trim();
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
