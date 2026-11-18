import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../playback/player_controller.dart';
import '../../../playback/playlist_advance_policy.dart';
import '../../../playback/player_ui_policies.dart';
import '../../../playback/sleep_timer_controller.dart';
import '../../../services/advanced_playback_controller.dart';
import '../../../services/playlist_service.dart';
import '../../../services/seek_preview_service.dart';
import '../../../services/settings_service.dart';
import '../../../theme/glass_decorations.dart';
import '../../../widgets/seek_slider.dart';
import '../../../widgets/transport_controls.dart';

const _seekBarSizeDuration = Duration(milliseconds: 190);

class PlayerBottomDock extends StatelessWidget {
  const PlayerBottomDock({
    super.key,
    required this.sleepTimer,
    required this.advancedPlayback,
    required this.player,
    required this.settings,
    required this.seekPreviewService,
    required this.hasMedia,
    required this.onSeekStart,
    required this.onSeekChange,
    required this.onSeekEnd,
    required this.onPlayPause,
    required this.onStop,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onOpenUrl,
    required this.onReopenLast,
    required this.onVolumeChanged,
    required this.onLoopModeChanged,
    required this.onRecentFileSelected,
    required this.onSettingsPressed,
    required this.onMoreActions,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleQueue,
    required this.onToggleMute,
    required this.onCycleSpeed,
    this.playlist,
  });

  final SleepTimerController sleepTimer;
  final AdvancedPlaybackController advancedPlayback;
  final PlayerController player;
  final SettingsService settings;
  final SeekPreviewService seekPreviewService;
  final bool hasMedia;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekChange;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenUrl;
  final VoidCallback onReopenLast;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<LoopMode> onLoopModeChanged;
  final ValueChanged<String> onRecentFileSelected;
  final VoidCallback onSettingsPressed;
  final ValueChanged<Rect> onMoreActions;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleQueue;
  final VoidCallback onToggleMute;
  final VoidCallback onCycleSpeed;
  final PlaylistService? playlist;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        sleepTimer,
        advancedPlayback,
        settings,
        ?playlist,
      ]),
      builder: (context, _) {
        final remaining = sleepTimer.remaining;
        final queue = playlist;
        return GlassChrome(
          borderOnTop: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (remaining != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.timer_outlined, size: 16),
                      label: Text(
                        '${AppLocalizations.of(context).menuSleepTimer} (${PlayerController.formatDuration(remaining)})',
                      ),
                      onDeleted: sleepTimer.cancel,
                    ),
                  ),
                ),
              AnimatedSize(
                duration: _seekBarSizeDuration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: player.duration.inMilliseconds > 0
                    ? Padding(
                        key: const ValueKey('seek-visible'),
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Row(
                          children: [
                            Text(
                              PlayerController.formatDuration(player.position),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Expanded(
                              child: SeekSliderWithHover(
                                position: player.position,
                                duration: player.duration,
                                previewService: seekPreviewService,
                                previewEnabled:
                                    PlayerUiPolicies.showSeekPreview(
                                      settings: settings,
                                      isAudioFile: player.isAudioFile,
                                    ),
                                markerPositions:
                                    settings.advancedPlaybackToolsEnabled
                                    ? advancedPlayback.markers
                                          .map(
                                            (marker) => SeekMarker(
                                              position: Duration(
                                                milliseconds: marker.positionMs,
                                              ),
                                              label: marker.label,
                                            ),
                                          )
                                          .toList(growable: false)
                                    : const [],
                                rangeStart:
                                    settings.advancedPlaybackToolsEnabled
                                    ? advancedPlayback.a
                                    : null,
                                rangeEnd: settings.advancedPlaybackToolsEnabled
                                    ? advancedPlayback.b
                                    : null,
                                onSeekStart: onSeekStart,
                                onSeekChange: onSeekChange,
                                onSeekEnd: onSeekEnd,
                              ),
                            ),
                            SeekDurationLabel(
                              key: const ValueKey('seek-duration-label'),
                              position: player.position,
                              duration: player.duration,
                              showRemaining: settings.showRemainingTime,
                              onToggle: () => settings.showRemainingTime =
                                  !settings.showRemainingTime,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('seek-hidden'),
                        width: double.infinity,
                      ),
              ),
              TransportControls(
                isPlaying: player.isPlaying,
                volume: player.volume,
                hasMedia: hasMedia,
                canGoPrevious: queue == null
                    ? null
                    : PlaylistAdvancePolicy.canGoPrevious(
                        queueLength: queue.length,
                        loopMode: settings.loopMode,
                        hasPreviousInOrder: queue.hasPrevious,
                      ),
                canGoNext: queue == null
                    ? null
                    : PlaylistAdvancePolicy.canGoNext(
                        queueLength: queue.length,
                        loopMode: settings.loopMode,
                        hasNextInOrder: queue.hasNext,
                      ),
                speed: settings.speed,
                loopMode: settings.loopMode,
                recentFiles: settings.recentFiles,
                onPlayPause: onPlayPause,
                onStop: onStop,
                onOpenFile: onOpenFile,
                onOpenFolder: onOpenFolder,
                onOpenUrl: onOpenUrl,
                onReopenLast: onReopenLast,
                onVolumeChanged: onVolumeChanged,
                onLoopModeChanged: onLoopModeChanged,
                onRecentFileSelected: onRecentFileSelected,
                onSettingsPressed: onSettingsPressed,
                onMoreActions: onMoreActions,
                onPrevious: onPrevious,
                onNext: onNext,
                onToggleQueue: onToggleQueue,
                onToggleMute: onToggleMute,
                onCycleSpeed: onCycleSpeed,
              ),
            ],
          ),
        );
      },
    );
  }
}
