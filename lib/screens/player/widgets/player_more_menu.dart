import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../playback/player_controller.dart';
import '../../../playback/playback_mix_policy.dart';
import '../../../playback/sleep_timer_controller.dart';
import '../../../services/playlist_service.dart';
import '../../../services/settings_service.dart';

const _sheetTransitionDuration = Duration(milliseconds: 180);

class PlayerMoreMenuActions {
  const PlayerMoreMenuActions({
    required this.onOpenUrl,
    required this.onAudioTracks,
    required this.onSubtitleTracks,
    required this.onExternalAudio,
    required this.onExternalSubtitle,
    required this.onChapters,
    required this.onEqualizer,
    required this.onAdvancedPlayback,
    required this.onScreenshot,
    required this.onSleepTimer,
    required this.onKeybinds,
    required this.onQueue,
    required this.onEnqueue,
    required this.onSetShuffle,
    required this.onCompact,
  });

  final VoidCallback onOpenUrl;
  final VoidCallback onAudioTracks;
  final VoidCallback onSubtitleTracks;
  final VoidCallback onExternalAudio;
  final VoidCallback onExternalSubtitle;
  final VoidCallback onChapters;
  final VoidCallback onEqualizer;
  final VoidCallback onAdvancedPlayback;
  final VoidCallback onScreenshot;
  final ValueChanged<int?> onSleepTimer;
  final VoidCallback onKeybinds;
  final VoidCallback onQueue;
  final VoidCallback onEnqueue;
  final ValueChanged<bool> onSetShuffle;
  final VoidCallback onCompact;
}

Widget _menuItem(
  BuildContext ctx,
  ColorScheme cs, {
  required IconData icon,
  required String label,
  required String action,
  Widget? trailing,
  Key? key,
}) {
  return InkWell(
    key: key,
    onTap: () => Navigator.pop(ctx, action),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurface),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          ?trailing,
        ],
      ),
    ),
  );
}

Widget _menuSwitchItem(
  BuildContext ctx, {
  required IconData icon,
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
  bool experimental = false,
}) {
  final cs = Theme.of(ctx).colorScheme;
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  final experimentalAmber = Color.lerp(cs.tertiary, Colors.amber, 0.72)!;
  final experimentalBackground = Color.alphaBlend(
    experimentalAmber.withValues(alpha: isDark ? 0.16 : 0.11),
    cs.surface,
  );
  final experimentalBorder = experimentalAmber.withValues(
    alpha: isDark ? 0.45 : 0.36,
  );
  final experimentalIcon = Color.lerp(
    experimentalAmber,
    isDark ? Colors.amber.shade200 : Colors.amber.shade700,
    0.22,
  )!;
  final child = InkWell(
    onTap: () => onChanged(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: experimental ? experimentalIcon : cs.onSurface,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Transform.scale(
            scale: 0.75,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    ),
  );
  if (!experimental) return child;
  return Padding(
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: experimentalBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: experimentalBorder),
      ),
      child: child,
    ),
  );
}

Future<String?> showPlayerMoreMenuSheet({
  required BuildContext context,
  required bool hasAudioOptions,
  required bool hasSubOptions,
  required bool hasChapters,
  required bool Function() hasCurrentFile,
  required bool Function() compactMode,
  required SettingsService settings,
  required SleepTimerController sleepTimer,
  required PlaylistService playlist,
  required ValueChanged<bool> onSetShuffle,
}) {
  final l10n = AppLocalizations.of(context);

  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context).dismissBarrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.20),
    transitionDuration: _sheetTransitionDuration,
    pageBuilder: (ctx, _, _) {
      final cs = Theme.of(ctx).colorScheme;
      var sleepExpanded = false;
      Widget item({
        required IconData icon,
        required String label,
        required String action,
        Widget? trailing,
        Key? key,
      }) {
        return _menuItem(
          ctx,
          cs,
          icon: icon,
          label: label,
          action: action,
          trailing: trailing,
          key: key,
        );
      }

      Widget switchItem({
        required IconData icon,
        required String label,
        required bool value,
        required ValueChanged<bool> onChanged,
        bool experimental = false,
      }) {
        return _menuSwitchItem(
          ctx,
          icon: icon,
          label: label,
          value: value,
          onChanged: onChanged,
          experimental: experimental,
        );
      }

      // Build the menu items as a compact, right-aligned vertical panel.
      return Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 64),
          child: Material(
            color: cs.surface.withValues(alpha: 0.97),
            elevation: 12,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 240,
                maxWidth: 280,
                maxHeight: 520,
              ),
              child: StatefulBuilder(
                builder: (ctx, setSheetState) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        item(
                          icon: Icons.link,
                          label: l10n.buttonOpenUrl,
                          action: 'open_url',
                        ),
                        const Divider(height: 1),
                        if (hasAudioOptions)
                          item(
                            icon: Icons.audiotrack,
                            label: l10n.dialogAudioTrackTitle,
                            action: 'audio',
                          ),
                        if (hasSubOptions)
                          item(
                            icon: Icons.subtitles,
                            label: l10n.dialogSubtitleTrackTitle,
                            action: 'subtitle',
                          ),
                        if (hasCurrentFile())
                          item(
                            icon: Icons.audio_file,
                            label: l10n.menuLoadExternalAudio,
                            action: 'external_audio',
                          ),
                        if (hasCurrentFile())
                          item(
                            icon: Icons.subtitles_outlined,
                            label: l10n.menuLoadExternalSubtitle,
                            action: 'external_subtitle',
                          ),
                        if (hasChapters)
                          item(
                            icon: Icons.menu_book,
                            label: l10n.dialogChaptersTitle,
                            action: 'chapters',
                          ),
                        item(
                          icon: Icons.graphic_eq,
                          label: l10n.dialogEqualizerTitle,
                          action: 'equalizer',
                        ),
                        if (settings.advancedPlaybackToolsEnabled)
                          item(
                            key: const ValueKey('advanced-playback-entry'),
                            icon: Icons.tune,
                            label: l10n.menuAdvancedPlayback,
                            action: 'advanced-playback',
                          ),
                        if (hasCurrentFile())
                          item(
                            icon: Icons.photo_camera,
                            label: l10n.menuTakeScreenshot,
                            action: 'screenshot',
                          ),
                        const Divider(height: 1),
                        ListenableBuilder(
                          listenable: sleepTimer,
                          builder: (context, _) {
                            final remaining = sleepTimer.remaining;
                            final sleepLabel = remaining == null
                                ? l10n.menuSleepTimer
                                : '${l10n.menuSleepTimer} (${PlayerController.formatDuration(remaining)})';
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  onTap: () => setSheetState(() {
                                    sleepExpanded = !sleepExpanded;
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.bedtime_outlined,
                                          size: 18,
                                          color: cs.onSurface,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            sleepLabel,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          sleepExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          size: 18,
                                          color: cs.onSurface,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (sleepExpanded) ...[
                                  item(
                                    icon: Icons.timer_off_outlined,
                                    label: l10n.menuSleepTimerOff,
                                    action: 'sleep_off',
                                  ),
                                  for (final minutes
                                      in SleepTimerController.presetMinutes)
                                    item(
                                      icon: Icons.timer_outlined,
                                      label: l10n.menuSleepTimerMinutes(
                                        minutes,
                                      ),
                                      action: 'sleep_$minutes',
                                    ),
                                ],
                              ],
                            );
                          },
                        ),
                        const Divider(height: 1),
                        if (hasAudioOptions &&
                            PlaybackMixPolicy.userFacingEnabled &&
                            settings.experimentalFeaturesEnabled)
                          switchItem(
                            icon: Icons.multitrack_audio,
                            label: l10n.menuMixAllAudioTracks,
                            value: settings.multiAudioMix,
                            experimental: true,
                            onChanged: (v) {
                              settings.multiAudioMix = v;
                              setSheetState(() {});
                            },
                          ),
                        item(
                          icon: Icons.keyboard,
                          label: l10n.dialogKeyboardShortcutsTitle,
                          action: 'keybinds',
                        ),
                        const Divider(height: 1),
                        item(
                          icon: Icons.queue_music,
                          label: playlist.isEmpty
                              ? l10n.menuQueueEmpty
                              : l10n.menuQueueCount(playlist.length),
                          action: 'queue',
                        ),
                        item(
                          icon: Icons.playlist_add,
                          label: l10n.menuAddFilesToQueue,
                          action: 'enqueue',
                        ),
                        switchItem(
                          icon: Icons.shuffle,
                          label: l10n.menuShuffleQueue,
                          value: settings.playlistShuffle,
                          onChanged: (v) {
                            onSetShuffle(v);
                            setSheetState(() {});
                          },
                        ),
                        switchItem(
                          icon: Icons.picture_in_picture_alt,
                          label: l10n.menuMiniPlayer,
                          value: compactMode(),
                          onChanged: (_) => Navigator.pop(ctx, 'compact'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

void dispatchPlayerMoreMenuResult(
  String? result,
  PlayerMoreMenuActions actions,
) {
  switch (result) {
    case 'open_url':
      actions.onOpenUrl();
      break;
    case 'audio':
      actions.onAudioTracks();
      break;
    case 'subtitle':
      actions.onSubtitleTracks();
      break;
    case 'external_audio':
      actions.onExternalAudio();
      break;
    case 'external_subtitle':
      actions.onExternalSubtitle();
      break;
    case 'chapters':
      actions.onChapters();
      break;
    case 'equalizer':
      actions.onEqualizer();
      break;
    case 'advanced-playback':
      actions.onAdvancedPlayback();
      break;
    case 'screenshot':
      actions.onScreenshot();
      break;
    case 'sleep_off':
      actions.onSleepTimer(null);
      break;
    case 'sleep_15':
      actions.onSleepTimer(15);
      break;
    case 'sleep_30':
      actions.onSleepTimer(30);
      break;
    case 'sleep_45':
      actions.onSleepTimer(45);
      break;
    case 'sleep_60':
      actions.onSleepTimer(60);
      break;
    case 'keybinds':
      actions.onKeybinds();
      break;
    case 'queue':
      actions.onQueue();
      break;
    case 'enqueue':
      actions.onEnqueue();
      break;
    case 'shuffle':
      // already toggled inline
      break;
    case 'compact':
      actions.onCompact();
      break;
  }
}
