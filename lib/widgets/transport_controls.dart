import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/playable_source.dart';
import '../playback/playback_speed_policy.dart';
import '../services/settings_service.dart';

class TransportControls extends StatelessWidget {
  static const double fullLayoutMinWidth = 848.0;

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
  final VoidCallback? onToggleMute;
  final VoidCallback? onCycleSpeed;

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
    this.onToggleMute,
    this.onCycleSpeed,
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

  List<String> get _recents => recentFiles
      .where((path) => path.trim().isNotEmpty)
      .take(10)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showVolumeSlider = screenWidth > 420;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= fullLayoutMinWidth
            ? _buildFullBar(context, l10n, showVolumeSlider)
            : _buildCompactBar(context, l10n),
      ),
    );
  }

  Widget _buildFullBar(
    BuildContext context,
    AppLocalizations l10n,
    bool showVolumeSlider,
  ) {
    return Row(
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
            _previousButton(l10n),
            _playPauseButton(l10n),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: l10n.tooltipStop,
              onPressed: hasMedia ? onStop : null,
              iconSize: 22,
            ),
            _nextButton(l10n),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(_loopIcon),
              tooltip: _loopTooltip(l10n),
              onPressed: _cycleLoopMode,
              iconSize: 20,
            ),
            // Speed control; tap to cycle presets
            _speedChip(l10n),
          ],
        ),

        // Right side: Volume and auxiliary actions
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _muteButton(l10n),
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
              ..._trailingButtons(l10n),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBar(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: l10n.tooltipOpenFile,
          onPressed: onOpenFile,
          visualDensity: VisualDensity.compact,
        ),
        _compactOverflowMenu(l10n),
        const Spacer(),
        _previousButton(l10n, compact: true),
        _playPauseButton(l10n),
        _nextButton(l10n, compact: true),
        const Spacer(),
        _muteButton(l10n),
        ..._trailingButtons(l10n, compact: true),
      ],
    );
  }

  Widget _compactOverflowMenu(AppLocalizations l10n) {
    final recents = _recents;
    return PopupMenuButton<VoidCallback>(
      key: const Key('transport-compact-overflow'),
      tooltip: l10n.tooltipMoreControls,
      icon: const Icon(Icons.expand_less),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem<VoidCallback>(
          value: onReopenLast,
          child: ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.tooltipReopenLast),
          ),
        ),
        if (onOpenFolder != null)
          PopupMenuItem<VoidCallback>(
            value: onOpenFolder!,
            child: ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: Text(l10n.tooltipOpenFolder),
            ),
          ),
        if (onOpenUrl != null)
          PopupMenuItem<VoidCallback>(
            value: onOpenUrl!,
            child: ListTile(
              leading: const Icon(Icons.link),
              title: Text(l10n.tooltipOpenUrl),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<VoidCallback>(
          value: onStop,
          enabled: hasMedia,
          child: ListTile(
            leading: const Icon(Icons.stop),
            title: Text(l10n.tooltipStop),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: _cycleLoopMode,
          child: ListTile(
            leading: Icon(_loopIcon),
            title: Text(_loopTooltip(l10n)),
          ),
        ),
        if (onCycleSpeed != null)
          PopupMenuItem<VoidCallback>(
            value: onCycleSpeed!,
            child: ListTile(
              leading: const Icon(Icons.speed),
              title: Text(l10n.tooltipCycleSpeed),
              trailing: Text(PlaybackSpeedPolicy.formatLabel(speed)),
            ),
          ),
        if (recents.isNotEmpty) const PopupMenuDivider(),
        for (final path in recents)
          PopupMenuItem<VoidCallback>(
            key: ValueKey<String>('compact-recent-$path'),
            value: () => onRecentFileSelected(path),
            child: Text(_recentLabel(path), overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }

  Widget _previousButton(AppLocalizations l10n, {bool compact = false}) {
    return IconButton(
      icon: const Icon(Icons.skip_previous),
      tooltip: l10n.tooltipPreviousTrack,
      onPressed: hasMedia ? onPrevious : null,
      iconSize: 22,
      visualDensity: compact ? VisualDensity.compact : null,
    );
  }

  Widget _nextButton(AppLocalizations l10n, {bool compact = false}) {
    return IconButton(
      icon: const Icon(Icons.skip_next),
      tooltip: l10n.tooltipNextTrack,
      onPressed: hasMedia ? onNext : null,
      iconSize: 22,
      visualDensity: compact ? VisualDensity.compact : null,
    );
  }

  Widget _playPauseButton(AppLocalizations l10n) {
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 170),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final scale = Tween<double>(begin: 0.86, end: 1.0).animate(animation);
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
    );
  }

  Widget _speedChip(AppLocalizations l10n) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            axis: Axis.horizontal,
            alignment: Alignment.centerLeft,
            sizeFactor: animation,
            child: child,
          ),
        );
      },
      child: Tooltip(
        key: ValueKey<double>(speed),
        message: l10n.tooltipCycleSpeed,
        child: TextButton(
          key: const Key('transport-speed-chip'),
          onPressed: onCycleSpeed,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            PlaybackSpeedPolicy.formatLabel(speed),
            style: TextStyle(
              fontSize: 12,
              fontWeight: speed == 1.0 ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _muteButton(AppLocalizations l10n) {
    return Semantics(
      label: volume == 0
          ? l10n.volumeMuted
          : l10n.volumePercent(volume.round()),
      button: onToggleMute != null,
      child: IconButton(
        icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up, size: 20),
        tooltip: volume == 0 ? l10n.tooltipUnmute : l10n.tooltipMute,
        onPressed: onToggleMute,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  List<Widget> _trailingButtons(AppLocalizations l10n, {bool compact = false}) {
    final density = compact ? VisualDensity.compact : null;
    return [
      // Queue toggle button
      IconButton(
        icon: const Icon(Icons.queue_music),
        tooltip: l10n.tooltipPlayQueue,
        iconSize: 20,
        visualDensity: density,
        onPressed: onToggleQueue,
      ),
      if (onMoreActions != null)
        IconButton(
          icon: const Icon(Icons.more_vert),
          tooltip: l10n.tooltipMore,
          iconSize: 20,
          visualDensity: density,
          // Always enabled: Open URL / keybinds / enqueue must work
          // on the empty state (Win/Linux have no File → Open URL).
          onPressed: onMoreActions,
        ),
      // Settings gear
      IconButton(
        icon: const Icon(Icons.settings),
        tooltip: l10n.tooltipSettings,
        iconSize: 20,
        visualDensity: density,
        onPressed: onSettingsPressed,
      ),
    ];
  }

  String _recentLabel(String path) {
    final source = PlayableSource.fromStored(path);
    final name = source?.displayName ?? p.basename(path).trim();
    return name.isEmpty ? path : name;
  }

  Widget _buildOpenButton(BuildContext context, AppLocalizations l10n) {
    final recents = _recents;

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
              return PopupMenuItem<String>(
                key: ValueKey<String>(path),
                value: path,
                child: Text(
                  _recentLabel(path),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
