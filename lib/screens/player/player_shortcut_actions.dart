import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/advanced_playback_controller.dart';
import '../../services/debug_log_service.dart';
import '../../services/instance_mode_service.dart';
import '../../services/player_service.dart';
import '../../services/player_shortcuts_service.dart';
import '../../services/settings_service.dart';
import 'player_log.dart';
import 'player_open_actions.dart';
import 'player_screenshot_action.dart';
import 'player_transport_controller.dart';
import 'player_window_controller.dart';
import 'source_load_coordinator.dart';
import 'track_chapter_controller.dart';

const _seekStep = Duration(seconds: 5);
const _seekStepBack = Duration(seconds: -5);

class PlayerShortcutActions {
  PlayerShortcutActions({
    required this.settings,
    required this.advancedPlayback,
    required this.playerService,
    required this.window,
    required this.transport,
    required this.tracks,
    required this.sourceLoad,
    required this.open,
    required this.screenshot,
    required this.log,
    required this.hasCurrentFile,
    required this.pulseOsd,
    required this.handleEscape,
  });

  final SettingsService settings;
  final AdvancedPlaybackController advancedPlayback;
  final IPlayerService playerService;
  final PlayerWindowController window;
  final PlayerTransportController transport;
  final TrackChapterController tracks;
  final SourceLoadCoordinator sourceLoad;
  final PlayerOpenActions open;
  final PlayerScreenshotAction screenshot;
  final PlayerDebugLog log;
  final bool Function() hasCurrentFile;
  final void Function() pulseOsd;
  final KeyEventResult Function() handleEscape;

  KeyEventResult handle(PlayerShortcutAction action) {
    switch (action) {
      case PlayerShortcutAction.openFile:
        log('shortcut_open_file', category: DebugLogCategory.ui);
        open.openFile();
        return KeyEventResult.handled;
      case PlayerShortcutAction.openUrl:
        log('shortcut_open_url', category: DebugLogCategory.ui);
        unawaited(open.openUrl());
        return KeyEventResult.handled;
      case PlayerShortcutAction.reopenLast:
        log('shortcut_reopen_last', category: DebugLogCategory.ui);
        unawaited(open.reopenLastFile());
        return KeyEventResult.handled;
      case PlayerShortcutAction.playPause:
        window.revealFullscreenChrome();
        unawaited(
          playerService.playPause().catchError((Object e) {
            log(
              'shortcut_play_pause_failed',
              category: DebugLogCategory.ui,
              message: e.toString(),
              severity: DebugSeverity.warn,
            );
          }),
        );
        log('shortcut_play_pause', category: DebugLogCategory.ui);
        return KeyEventResult.handled;
      case PlayerShortcutAction.seekForward:
        log('shortcut_seek_forward', category: DebugLogCategory.ui);
        window.revealFullscreenChrome();
        pulseOsd();
        transport.seekRelative(_seekStep);
        return KeyEventResult.handled;
      case PlayerShortcutAction.seekBack:
        log('shortcut_seek_back', category: DebugLogCategory.ui);
        window.revealFullscreenChrome();
        pulseOsd();
        transport.seekRelative(_seekStepBack);
        return KeyEventResult.handled;
      case PlayerShortcutAction.volumeUp:
        log('shortcut_volume_up', category: DebugLogCategory.ui);
        transport.adjustVolume(5);
        return KeyEventResult.handled;
      case PlayerShortcutAction.volumeDown:
        log('shortcut_volume_down', category: DebugLogCategory.ui);
        transport.adjustVolume(-5);
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleMute:
        log('shortcut_toggle_mute', category: DebugLogCategory.ui);
        transport.toggleMute();
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleFullscreen:
        log('shortcut_toggle_fullscreen', category: DebugLogCategory.ui);
        window.revealFullscreenChrome();
        unawaited(window.toggleFullscreen());
        return KeyEventResult.handled;
      case PlayerShortcutAction.exitFullscreen:
        // Bare Escape is handled above; keep this for custom/accelerator paths.
        return handleEscape();
      case PlayerShortcutAction.chapterNext:
        if (transport.canStepVideoFrame) {
          log('shortcut_frame_forward', category: DebugLogCategory.ui);
          unawaited(transport.stepFrame(forward: true));
          return KeyEventResult.handled;
        }
        log('shortcut_chapter_next', category: DebugLogCategory.ui);
        unawaited(tracks.stepChapter(1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.chapterPrev:
        if (transport.canStepVideoFrame) {
          log('shortcut_frame_back', category: DebugLogCategory.ui);
          unawaited(transport.stepFrame(forward: false));
          return KeyEventResult.handled;
        }
        log('shortcut_chapter_prev', category: DebugLogCategory.ui);
        unawaited(tracks.stepChapter(-1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.screenshot:
        log('shortcut_screenshot', category: DebugLogCategory.ui);
        unawaited(screenshot.take());
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleAudioTrack:
        log('shortcut_cycle_audio', category: DebugLogCategory.ui);
        unawaited(tracks.cycleAudioTrack());
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleSubtitleTrack:
        log('shortcut_cycle_sub', category: DebugLogCategory.ui);
        unawaited(tracks.cycleSubtitleTrack());
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleSubtitle:
        log('shortcut_toggle_sub', category: DebugLogCategory.ui);
        unawaited(tracks.toggleSubtitleVisibility());
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleEqualizer:
        log('shortcut_toggle_eq', category: DebugLogCategory.ui);
        tracks.toggleEqualizer();
        return KeyEventResult.handled;
      case PlayerShortcutAction.playlistNext:
        log('shortcut_playlist_next', category: DebugLogCategory.ui);
        unawaited(sourceLoad.advancePlaylist(1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.playlistPrev:
        log('shortcut_playlist_prev', category: DebugLogCategory.ui);
        unawaited(sourceLoad.advancePlaylist(-1));
        return KeyEventResult.handled;
      case PlayerShortcutAction.toggleCompactMode:
        log('shortcut_toggle_compact', category: DebugLogCategory.ui);
        unawaited(window.toggleCompactMode());
        return KeyEventResult.handled;
      case PlayerShortcutAction.newWindow:
        log('shortcut_new_window', category: DebugLogCategory.ui);
        unawaited(InstanceModeService.openNewWindow());
        return KeyEventResult.handled;
      case PlayerShortcutAction.speedSlower:
        log('shortcut_speed_slower', category: DebugLogCategory.ui);
        transport.nudgePlaybackSpeed(faster: false);
        return KeyEventResult.handled;
      case PlayerShortcutAction.speedFaster:
        log('shortcut_speed_faster', category: DebugLogCategory.ui);
        transport.nudgePlaybackSpeed(faster: true);
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleSpeed:
        log('shortcut_cycle_speed', category: DebugLogCategory.ui);
        transport.cyclePlaybackSpeed();
        return KeyEventResult.handled;
      case PlayerShortcutAction.cycleAdvancedLoop:
        if (!settings.advancedPlaybackToolsEnabled || !hasCurrentFile()) {
          return KeyEventResult.ignored;
        }
        unawaited(advancedPlayback.cycleLoop());
        return KeyEventResult.handled;
      case PlayerShortcutAction.subtitleDelayBack:
        if (!settings.advancedPlaybackToolsEnabled || !hasCurrentFile()) {
          return KeyEventResult.ignored;
        }
        unawaited(advancedPlayback.adjustSubtitleDelay(-100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.subtitleDelayForward:
        if (!settings.advancedPlaybackToolsEnabled || !hasCurrentFile()) {
          return KeyEventResult.ignored;
        }
        unawaited(advancedPlayback.adjustSubtitleDelay(100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.audioDelayBack:
        if (!settings.advancedPlaybackToolsEnabled || !hasCurrentFile()) {
          return KeyEventResult.ignored;
        }
        unawaited(advancedPlayback.adjustAudioDelay(-100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.audioDelayForward:
        if (!settings.advancedPlaybackToolsEnabled || !hasCurrentFile()) {
          return KeyEventResult.ignored;
        }
        unawaited(advancedPlayback.adjustAudioDelay(100));
        return KeyEventResult.handled;
      case PlayerShortcutAction.addPlaybackMarker:
        if (!settings.advancedPlaybackToolsEnabled || !hasCurrentFile()) {
          return KeyEventResult.ignored;
        }
        advancedPlayback.addMarker();
        return KeyEventResult.handled;
    }
  }
}
